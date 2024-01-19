-- Copyright 2023 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
local test = require "integration_test"
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local clusters = require "st.zigbee.zcl.clusters"

local Thermostat = clusters.Thermostat
local capabilities = require "st.capabilities"

local mock_device = test.mock_device.build_test_zigbee_device({
  profile = t_utils.get_profile_definition("thermostat-resideo-dt300st-m000.yml"),
  zigbee_endpoints = {
    [1] = {
      id = 1,
      manufacturer = "Resideo Korea",
      model = "DT300ST-M000",
      server_clusters = {0x0201, 0x0402}
    }
  }
})

-- Room 1 (2nd Thermostat)
local mock_first_child = test.mock_device.build_test_child_device({
  profile = t_utils.get_profile_definition("thermostat-resideo-dt300st-m000.yml"),
  device_network_id = string.format("%04X:%02X", mock_device:get_short_address(), 2),
  parent_device_id = mock_device.id,
  parent_assigned_child_key = string.format("%02X", 2)
})

-- Room 2 (3rd Thermostat)
local mock_second_child = test.mock_device.build_test_child_device({
  profile = t_utils.get_profile_definition("thermostat-resideo-dt300st-m000.yml"),
  device_network_id = string.format("%04X:%02X", mock_device:get_short_address(), 3),
  parent_device_id = mock_device.id,
  parent_assigned_child_key = string.format("%02X", 3)
})

-- Room 3 (4th Thermostat)
local mock_third_child = test.mock_device.build_test_child_device({
  profile = t_utils.get_profile_definition("thermostat-resideo-dt300st-m000.yml"),
  device_network_id = string.format("%04X:%02X", mock_device:get_short_address(), 4),
  parent_device_id = mock_device.id,
  parent_assigned_child_key = string.format("%02X", 4)
})

-- Room 4 (5th Thermostat)
local mock_forth_child = test.mock_device.build_test_child_device({
  profile = t_utils.get_profile_definition("thermostat-resideo-dt300st-m000.yml"),
  device_network_id = string.format("%04X:%02X", mock_device:get_short_address(), 5),
  parent_device_id = mock_device.id,
  parent_assigned_child_key = string.format("%02X", 5)
})

-- Room 5 (6th Thermostat)
local mock_fifth_child = test.mock_device.build_test_child_device({
  profile = t_utils.get_profile_definition("thermostat-resideo-dt300st-m000.yml"),
  device_network_id = string.format("%04X:%02X", mock_device:get_short_address(), 6),
  parent_device_id = mock_device.id,
  parent_assigned_child_key = string.format("%02X", 6)
})

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
  test.mock_device.add_test_device(mock_first_child)
  test.mock_device.add_test_device(mock_second_child)
  test.mock_device.add_test_device(mock_third_child)
  test.mock_device.add_test_device(mock_forth_child)
  test.mock_device.add_test_device(mock_fifth_child)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

test.register_coroutine_test("Configure should configure all necessary attributes", function()
  test.socket.zigbee:__set_channel_ordering("relaxed")
  test.socket.device_lifecycle:__queue_receive({mock_device.id, "doConfigure"})
  for endpoint = 1, 6 do
    test.socket.zigbee:__expect_send({mock_device.id,
                                      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui,
      Thermostat.ID, endpoint)})
  end

  test.socket.zigbee:__expect_send({mock_device.id,
                                    Thermostat.attributes.OccupiedHeatingSetpoint:configure_reporting(mock_device, 20,
    300, 100)})
  test.socket.zigbee:__expect_send({mock_device.id,
                                    Thermostat.attributes.LocalTemperature:configure_reporting(mock_device, 20, 300, 100)})
  test.socket.zigbee:__expect_send({mock_device.id,
                                    Thermostat.attributes.ThermostatRunningState:configure_reporting(mock_device, 20,
    300)})
  test.socket.zigbee:__expect_send({mock_device.id,
                                    Thermostat.attributes.SystemMode:configure_reporting(mock_device, 20, 300)})

  local attributes = {Thermostat.attributes.OccupiedHeatingSetpoint, Thermostat.attributes.LocalTemperature,
                      Thermostat.attributes.ControlSequenceOfOperation, Thermostat.attributes.ThermostatRunningState,
                      Thermostat.attributes.SystemMode}
  for _, attribute in pairs(attributes) do
    test.socket.zigbee:__expect_send({mock_device.id, attribute:read(mock_device)})
  end
  mock_device:expect_metadata_update({
    provisioning_state = "PROVISIONED"
  })
end)

--------------------------------------------------------------------------------
-- Parent thermostat device

test.register_coroutine_test("Refresh should read all necessary attributes", function()
  test.socket.zigbee:__set_channel_ordering("relaxed")
  test.socket.capability:__queue_receive({mock_device.id, {
    capability = "refresh",
    component = "main",
    command = "refresh",
    args = {}
  }})
  local attributes = {Thermostat.attributes.OccupiedHeatingSetpoint, Thermostat.attributes.LocalTemperature,
                      Thermostat.attributes.ControlSequenceOfOperation, Thermostat.attributes.ThermostatRunningState,
                      Thermostat.attributes.SystemMode}
  for _, attribute in pairs(attributes) do
    test.socket.zigbee:__expect_send({mock_device.id, attribute:read(mock_device)})
  end
end)

test.register_coroutine_test("Temperature reporting should create the appropriate events", function()
  test.socket.zigbee:__queue_receive({mock_device.id,
                                      Thermostat.attributes.LocalTemperature:build_test_attr_report(mock_device, 2100)})
  test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.temperatureMeasurement.temperature({
      value = 21.0,
      unit = "C"
    })))
end)

test.register_coroutine_test("Thermostat mode reporting should create the appropriate events", function()
  test.socket.zigbee:__queue_receive({mock_device.id,
                                      Thermostat.attributes.SystemMode:build_test_attr_report(mock_device,
    Thermostat.attributes.SystemMode.OFF)})
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.thermostatMode
    .thermostatMode.away()))
  test.socket.zigbee:__queue_receive({mock_device.id,
                                      Thermostat.attributes.SystemMode:build_test_attr_report(mock_device,
    Thermostat.attributes.SystemMode.HEAT)})
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.thermostatMode
    .thermostatMode.heat()))
end)

test.register_coroutine_test("ControlSequenceOfOperation reporting should create the appropriate events", function()
  test.socket.zigbee:__queue_receive({mock_device.id,
                                      Thermostat.attributes.ControlSequenceOfOperation:build_test_attr_report(
    mock_device, 0x02)})
  test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.thermostatMode.supportedThermostatModes({"away", "heat"}, {
      visibility = {
        displayed = false
      }
    })))
end)

test.register_coroutine_test("OccupiedHeatingSetpoint reporting shoulb create the appropriate events", function()
  test.socket.zigbee:__queue_receive({mock_device.id,
                                      Thermostat.attributes.OccupiedHeatingSetpoint:build_test_attr_report(mock_device,
    2100)})
  test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.thermostatHeatingSetpoint.heatingSetpoint({
      value = 21.0,
      unit = "C"
    })))
end)

test.register_coroutine_test("Setting the heating setpoint should generate the appropriate messages", function()
  test.socket.capability:__queue_receive({mock_device.id, {
    component = "main",
    capability = capabilities.thermostatHeatingSetpoint.ID,
    command = "setHeatingSetpoint",
    args = {21}
  }})
  test.socket.zigbee:__expect_send({mock_device.id,
                                    Thermostat.attributes.OccupiedHeatingSetpoint:write(mock_device, 2100)})
end)

test.register_coroutine_test("Setting the thermostat mode to away should generate the appropriate messages", function()
  test.socket.capability:__queue_receive({mock_device.id, {
    component = "main",
    capability = capabilities.thermostatMode.ID,
    command = "setThermostatMode",
    args = {"away"}
  }})
  test.socket.zigbee:__expect_send({mock_device.id,
                                    Thermostat.attributes.SystemMode:write(mock_device,
    Thermostat.attributes.SystemMode.OFF)})
end)

test.register_coroutine_test("Setting the thermostat mode to heat should generate the appropriate messages", function()
  test.socket.capability:__queue_receive({mock_device.id, {
    component = "main",
    capability = capabilities.thermostatMode.ID,
    command = "heat",
    args = {}
  }})
  test.socket.zigbee:__expect_send({mock_device.id,
                                    Thermostat.attributes.SystemMode:write(mock_device,
    Thermostat.attributes.SystemMode.HEAT)})
end)

--------------------------------------------------------------------------------
-- First child thermostat device

test.register_coroutine_test("Refresh should read all necessary attributes with first child device", function()
  test.socket.zigbee:__set_channel_ordering("relaxed")
  test.socket.capability:__queue_receive({mock_first_child.id, {
    capability = "refresh",
    component = "main",
    command = "refresh",
    args = {}
  }})
  local attributes = {Thermostat.attributes.OccupiedHeatingSetpoint, Thermostat.attributes.LocalTemperature,
                      Thermostat.attributes.ControlSequenceOfOperation, Thermostat.attributes.ThermostatRunningState,
                      Thermostat.attributes.SystemMode}
  for _, attribute in pairs(attributes) do
    test.socket.zigbee:__expect_send({mock_device.id, attribute:read(mock_first_child)})
  end
end)

test.register_coroutine_test("Temperature reporting should create the appropriate events with first child device", function()
  test.socket.zigbee:__queue_receive({mock_first_child.id,
                                      Thermostat.attributes.LocalTemperature:build_test_attr_report(mock_first_child, 2100)})
  test.socket.capability:__expect_send(mock_first_child:generate_test_message("main",
    capabilities.temperatureMeasurement.temperature({
      value = 21.0,
      unit = "C"
    })))
end)

test.register_coroutine_test("Thermostat mode reporting should create the appropriate events with first child device", function()
  test.socket.zigbee:__queue_receive({mock_first_child.id,
                                      Thermostat.attributes.SystemMode:build_test_attr_report(mock_first_child,
    Thermostat.attributes.SystemMode.OFF)})
  test.socket.capability:__expect_send(mock_first_child:generate_test_message("main", capabilities.thermostatMode
    .thermostatMode.away()))
  test.socket.zigbee:__queue_receive({mock_first_child.id,
                                      Thermostat.attributes.SystemMode:build_test_attr_report(mock_first_child,
    Thermostat.attributes.SystemMode.HEAT)})
  test.socket.capability:__expect_send(mock_first_child:generate_test_message("main", capabilities.thermostatMode
    .thermostatMode.heat()))
end)

test.register_coroutine_test("ControlSequenceOfOperation reporting should create the appropriate events with first child device", function()
  test.socket.zigbee:__queue_receive({mock_first_child.id,
                                      Thermostat.attributes.ControlSequenceOfOperation:build_test_attr_report(
    mock_first_child, 0x02)})
  test.socket.capability:__expect_send(mock_first_child:generate_test_message("main",
    capabilities.thermostatMode.supportedThermostatModes({"away", "heat"}, {
      visibility = {
        displayed = false
      }
    })))
end)

test.register_coroutine_test("OccupiedHeatingSetpoint reporting shoulb create the appropriate events with first child device", function()
  test.socket.zigbee:__queue_receive({mock_first_child.id,
                                      Thermostat.attributes.OccupiedHeatingSetpoint:build_test_attr_report(mock_first_child,
    2100)})
  test.socket.capability:__expect_send(mock_first_child:generate_test_message("main",
    capabilities.thermostatHeatingSetpoint.heatingSetpoint({
      value = 21.0,
      unit = "C"
    })))
end)

test.register_coroutine_test("Setting the heating setpoint should generate the appropriate messages with first child device", function()
  test.socket.capability:__queue_receive({mock_first_child.id, {
    component = "main",
    capability = capabilities.thermostatHeatingSetpoint.ID,
    command = "setHeatingSetpoint",
    args = {21}
  }})
  test.socket.zigbee:__expect_send({mock_device.id,
                                    Thermostat.attributes.OccupiedHeatingSetpoint:write(mock_first_child, 2100)})
end)

test.register_coroutine_test("Setting the thermostat mode to away should generate the appropriate messages with first child device", function()
  test.socket.capability:__queue_receive({mock_first_child.id, {
    component = "main",
    capability = capabilities.thermostatMode.ID,
    command = "setThermostatMode",
    args = {"away"}
  }})
  test.socket.zigbee:__expect_send({mock_device.id,
                                    Thermostat.attributes.SystemMode:write(mock_first_child,
    Thermostat.attributes.SystemMode.OFF)})
end)

test.register_coroutine_test("Setting the thermostat mode to heat should generate the appropriate messages with first child device", function()
  test.socket.capability:__queue_receive({mock_first_child.id, {
    component = "main",
    capability = capabilities.thermostatMode.ID,
    command = "heat",
    args = {}
  }})
  test.socket.zigbee:__expect_send({mock_device.id,
                                    Thermostat.attributes.SystemMode:write(mock_first_child,
    Thermostat.attributes.SystemMode.HEAT)})
end)

--------------------------------------------------------------------------------
-- Second child thermostat device

test.register_coroutine_test("Refresh should read all necessary attributes with second child device", function()
  test.socket.zigbee:__set_channel_ordering("relaxed")
  test.socket.capability:__queue_receive({mock_second_child.id, {
    capability = "refresh",
    component = "main",
    command = "refresh",
    args = {}
  }})
  local attributes = {Thermostat.attributes.OccupiedHeatingSetpoint, Thermostat.attributes.LocalTemperature,
                      Thermostat.attributes.ControlSequenceOfOperation, Thermostat.attributes.ThermostatRunningState,
                      Thermostat.attributes.SystemMode}
  for _, attribute in pairs(attributes) do
    test.socket.zigbee:__expect_send({mock_device.id, attribute:read(mock_second_child)})
  end
end)

test.register_coroutine_test("Temperature reporting should create the appropriate events with second child device", function()
  test.socket.zigbee:__queue_receive({mock_second_child.id,
                                      Thermostat.attributes.LocalTemperature:build_test_attr_report(mock_second_child, 2100)})
  test.socket.capability:__expect_send(mock_second_child:generate_test_message("main",
    capabilities.temperatureMeasurement.temperature({
      value = 21.0,
      unit = "C"
    })))
end)

test.register_coroutine_test("Thermostat mode reporting should create the appropriate events with second child device", function()
  test.socket.zigbee:__queue_receive({mock_second_child.id,
                                      Thermostat.attributes.SystemMode:build_test_attr_report(mock_second_child,
    Thermostat.attributes.SystemMode.OFF)})
  test.socket.capability:__expect_send(mock_second_child:generate_test_message("main", capabilities.thermostatMode
    .thermostatMode.away()))
  test.socket.zigbee:__queue_receive({mock_second_child.id,
                                      Thermostat.attributes.SystemMode:build_test_attr_report(mock_second_child,
    Thermostat.attributes.SystemMode.HEAT)})
  test.socket.capability:__expect_send(mock_second_child:generate_test_message("main", capabilities.thermostatMode
    .thermostatMode.heat()))
end)

test.register_coroutine_test("ControlSequenceOfOperation reporting should create the appropriate events with second child device", function()
  test.socket.zigbee:__queue_receive({mock_second_child.id,
                                      Thermostat.attributes.ControlSequenceOfOperation:build_test_attr_report(
    mock_second_child, 0x02)})
  test.socket.capability:__expect_send(mock_second_child:generate_test_message("main",
    capabilities.thermostatMode.supportedThermostatModes({"away", "heat"}, {
      visibility = {
        displayed = false
      }
    })))
end)

test.register_coroutine_test("OccupiedHeatingSetpoint reporting shoulb create the appropriate events with second child device", function()
  test.socket.zigbee:__queue_receive({mock_second_child.id,
                                      Thermostat.attributes.OccupiedHeatingSetpoint:build_test_attr_report(mock_second_child,
    2100)})
  test.socket.capability:__expect_send(mock_second_child:generate_test_message("main",
    capabilities.thermostatHeatingSetpoint.heatingSetpoint({
      value = 21.0,
      unit = "C"
    })))
end)

test.register_coroutine_test("Setting the heating setpoint should generate the appropriate messages with second child device", function()
  test.socket.capability:__queue_receive({mock_second_child.id, {
    component = "main",
    capability = capabilities.thermostatHeatingSetpoint.ID,
    command = "setHeatingSetpoint",
    args = {21}
  }})
  test.socket.zigbee:__expect_send({mock_device.id,
                                    Thermostat.attributes.OccupiedHeatingSetpoint:write(mock_second_child, 2100)})
end)

test.register_coroutine_test("Setting the thermostat mode to away should generate the appropriate messages with second child device", function()
  test.socket.capability:__queue_receive({mock_second_child.id, {
    component = "main",
    capability = capabilities.thermostatMode.ID,
    command = "setThermostatMode",
    args = {"away"}
  }})
  test.socket.zigbee:__expect_send({mock_device.id,
                                    Thermostat.attributes.SystemMode:write(mock_second_child,
    Thermostat.attributes.SystemMode.OFF)})
end)

test.register_coroutine_test("Setting the thermostat mode to heat should generate the appropriate messages with second child device", function()
  test.socket.capability:__queue_receive({mock_second_child.id, {
    component = "main",
    capability = capabilities.thermostatMode.ID,
    command = "heat",
    args = {}
  }})
  test.socket.zigbee:__expect_send({mock_device.id,
                                    Thermostat.attributes.SystemMode:write(mock_second_child,
    Thermostat.attributes.SystemMode.HEAT)})
end)

--------------------------------------------------------------------------------
-- Third child thermostat device

test.register_coroutine_test("Refresh should read all necessary attributes with third child device", function()
  test.socket.zigbee:__set_channel_ordering("relaxed")
  test.socket.capability:__queue_receive({mock_third_child.id, {
    capability = "refresh",
    component = "main",
    command = "refresh",
    args = {}
  }})
  local attributes = {Thermostat.attributes.OccupiedHeatingSetpoint, Thermostat.attributes.LocalTemperature,
                      Thermostat.attributes.ControlSequenceOfOperation, Thermostat.attributes.ThermostatRunningState,
                      Thermostat.attributes.SystemMode}
  for _, attribute in pairs(attributes) do
    test.socket.zigbee:__expect_send({mock_device.id, attribute:read(mock_third_child)})
  end
end)

test.register_coroutine_test("Temperature reporting should create the appropriate events with third child device", function()
  test.socket.zigbee:__queue_receive({mock_third_child.id,
                                      Thermostat.attributes.LocalTemperature:build_test_attr_report(mock_third_child, 2100)})
  test.socket.capability:__expect_send(mock_third_child:generate_test_message("main",
    capabilities.temperatureMeasurement.temperature({
      value = 21.0,
      unit = "C"
    })))
end)

test.register_coroutine_test("Thermostat mode reporting should create the appropriate events with third child device", function()
  test.socket.zigbee:__queue_receive({mock_third_child.id,
                                      Thermostat.attributes.SystemMode:build_test_attr_report(mock_third_child,
    Thermostat.attributes.SystemMode.OFF)})
  test.socket.capability:__expect_send(mock_third_child:generate_test_message("main", capabilities.thermostatMode
    .thermostatMode.away()))
  test.socket.zigbee:__queue_receive({mock_third_child.id,
                                      Thermostat.attributes.SystemMode:build_test_attr_report(mock_third_child,
    Thermostat.attributes.SystemMode.HEAT)})
  test.socket.capability:__expect_send(mock_third_child:generate_test_message("main", capabilities.thermostatMode
    .thermostatMode.heat()))
end)

test.register_coroutine_test("ControlSequenceOfOperation reporting should create the appropriate events with third child device", function()
  test.socket.zigbee:__queue_receive({mock_third_child.id,
                                      Thermostat.attributes.ControlSequenceOfOperation:build_test_attr_report(
    mock_third_child, 0x02)})
  test.socket.capability:__expect_send(mock_third_child:generate_test_message("main",
    capabilities.thermostatMode.supportedThermostatModes({"away", "heat"}, {
      visibility = {
        displayed = false
      }
    })))
end)

test.register_coroutine_test("OccupiedHeatingSetpoint reporting shoulb create the appropriate events with third child device", function()
  test.socket.zigbee:__queue_receive({mock_third_child.id,
                                      Thermostat.attributes.OccupiedHeatingSetpoint:build_test_attr_report(mock_third_child,
    2100)})
  test.socket.capability:__expect_send(mock_third_child:generate_test_message("main",
    capabilities.thermostatHeatingSetpoint.heatingSetpoint({
      value = 21.0,
      unit = "C"
    })))
end)

test.register_coroutine_test("Setting the heating setpoint should generate the appropriate messages with third child device", function()
  test.socket.capability:__queue_receive({mock_third_child.id, {
    component = "main",
    capability = capabilities.thermostatHeatingSetpoint.ID,
    command = "setHeatingSetpoint",
    args = {21}
  }})
  test.socket.zigbee:__expect_send({mock_device.id,
                                    Thermostat.attributes.OccupiedHeatingSetpoint:write(mock_third_child, 2100)})
end)

test.register_coroutine_test("Setting the thermostat mode to away should generate the appropriate messages with third child device", function()
  test.socket.capability:__queue_receive({mock_third_child.id, {
    component = "main",
    capability = capabilities.thermostatMode.ID,
    command = "setThermostatMode",
    args = {"away"}
  }})
  test.socket.zigbee:__expect_send({mock_device.id,
                                    Thermostat.attributes.SystemMode:write(mock_third_child,
    Thermostat.attributes.SystemMode.OFF)})
end)

test.register_coroutine_test("Setting the thermostat mode to heat should generate the appropriate messages with third child device", function()
  test.socket.capability:__queue_receive({mock_third_child.id, {
    component = "main",
    capability = capabilities.thermostatMode.ID,
    command = "heat",
    args = {}
  }})
  test.socket.zigbee:__expect_send({mock_device.id,
                                    Thermostat.attributes.SystemMode:write(mock_third_child,
    Thermostat.attributes.SystemMode.HEAT)})
end)

--------------------------------------------------------------------------------
-- Forth child thermostat device

test.register_coroutine_test("Refresh should read all necessary attributes with forth child device", function()
  test.socket.zigbee:__set_channel_ordering("relaxed")
  test.socket.capability:__queue_receive({mock_forth_child.id, {
    capability = "refresh",
    component = "main",
    command = "refresh",
    args = {}
  }})
  local attributes = {Thermostat.attributes.OccupiedHeatingSetpoint, Thermostat.attributes.LocalTemperature,
                      Thermostat.attributes.ControlSequenceOfOperation, Thermostat.attributes.ThermostatRunningState,
                      Thermostat.attributes.SystemMode}
  for _, attribute in pairs(attributes) do
    test.socket.zigbee:__expect_send({mock_device.id, attribute:read(mock_forth_child)})
  end
end)

test.register_coroutine_test("Temperature reporting should create the appropriate events with forth child device", function()
  test.socket.zigbee:__queue_receive({mock_forth_child.id,
                                      Thermostat.attributes.LocalTemperature:build_test_attr_report(mock_forth_child, 2100)})
  test.socket.capability:__expect_send(mock_forth_child:generate_test_message("main",
    capabilities.temperatureMeasurement.temperature({
      value = 21.0,
      unit = "C"
    })))
end)

test.register_coroutine_test("Thermostat mode reporting should create the appropriate events with forth child device", function()
  test.socket.zigbee:__queue_receive({mock_forth_child.id,
                                      Thermostat.attributes.SystemMode:build_test_attr_report(mock_forth_child,
    Thermostat.attributes.SystemMode.OFF)})
  test.socket.capability:__expect_send(mock_forth_child:generate_test_message("main", capabilities.thermostatMode
    .thermostatMode.away()))
  test.socket.zigbee:__queue_receive({mock_forth_child.id,
                                      Thermostat.attributes.SystemMode:build_test_attr_report(mock_forth_child,
    Thermostat.attributes.SystemMode.HEAT)})
  test.socket.capability:__expect_send(mock_forth_child:generate_test_message("main", capabilities.thermostatMode
    .thermostatMode.heat()))
end)

test.register_coroutine_test("ControlSequenceOfOperation reporting should create the appropriate events with forth child device", function()
  test.socket.zigbee:__queue_receive({mock_forth_child.id,
                                      Thermostat.attributes.ControlSequenceOfOperation:build_test_attr_report(
    mock_forth_child, 0x02)})
  test.socket.capability:__expect_send(mock_forth_child:generate_test_message("main",
    capabilities.thermostatMode.supportedThermostatModes({"away", "heat"}, {
      visibility = {
        displayed = false
      }
    })))
end)

test.register_coroutine_test("OccupiedHeatingSetpoint reporting shoulb create the appropriate events with forth child device", function()
  test.socket.zigbee:__queue_receive({mock_forth_child.id,
                                      Thermostat.attributes.OccupiedHeatingSetpoint:build_test_attr_report(mock_forth_child,
    2100)})
  test.socket.capability:__expect_send(mock_forth_child:generate_test_message("main",
    capabilities.thermostatHeatingSetpoint.heatingSetpoint({
      value = 21.0,
      unit = "C"
    })))
end)

test.register_coroutine_test("Setting the heating setpoint should generate the appropriate messages with forth child device", function()
  test.socket.capability:__queue_receive({mock_forth_child.id, {
    component = "main",
    capability = capabilities.thermostatHeatingSetpoint.ID,
    command = "setHeatingSetpoint",
    args = {21}
  }})
  test.socket.zigbee:__expect_send({mock_device.id,
                                    Thermostat.attributes.OccupiedHeatingSetpoint:write(mock_forth_child, 2100)})
end)

test.register_coroutine_test("Setting the thermostat mode to away should generate the appropriate messages with forth child device", function()
  test.socket.capability:__queue_receive({mock_forth_child.id, {
    component = "main",
    capability = capabilities.thermostatMode.ID,
    command = "setThermostatMode",
    args = {"away"}
  }})
  test.socket.zigbee:__expect_send({mock_device.id,
                                    Thermostat.attributes.SystemMode:write(mock_forth_child,
    Thermostat.attributes.SystemMode.OFF)})
end)

test.register_coroutine_test("Setting the thermostat mode to heat should generate the appropriate messages with forth child device", function()
  test.socket.capability:__queue_receive({mock_forth_child.id, {
    component = "main",
    capability = capabilities.thermostatMode.ID,
    command = "heat",
    args = {}
  }})
  test.socket.zigbee:__expect_send({mock_device.id,
                                    Thermostat.attributes.SystemMode:write(mock_forth_child,
    Thermostat.attributes.SystemMode.HEAT)})
end)

--------------------------------------------------------------------------------
-- Fifth child thermostat device

test.register_coroutine_test("Refresh should read all necessary attributes with fifth child device", function()
  test.socket.zigbee:__set_channel_ordering("relaxed")
  test.socket.capability:__queue_receive({mock_fifth_child.id, {
    capability = "refresh",
    component = "main",
    command = "refresh",
    args = {}
  }})
  local attributes = {Thermostat.attributes.OccupiedHeatingSetpoint, Thermostat.attributes.LocalTemperature,
                      Thermostat.attributes.ControlSequenceOfOperation, Thermostat.attributes.ThermostatRunningState,
                      Thermostat.attributes.SystemMode}
  for _, attribute in pairs(attributes) do
    test.socket.zigbee:__expect_send({mock_device.id, attribute:read(mock_fifth_child)})
  end
end)

test.register_coroutine_test("Temperature reporting should create the appropriate events with fifth child device", function()
  test.socket.zigbee:__queue_receive({mock_fifth_child.id,
                                      Thermostat.attributes.LocalTemperature:build_test_attr_report(mock_fifth_child, 2100)})
  test.socket.capability:__expect_send(mock_fifth_child:generate_test_message("main",
    capabilities.temperatureMeasurement.temperature({
      value = 21.0,
      unit = "C"
    })))
end)

test.register_coroutine_test("Thermostat mode reporting should create the appropriate events with fifth child device", function()
  test.socket.zigbee:__queue_receive({mock_fifth_child.id,
                                      Thermostat.attributes.SystemMode:build_test_attr_report(mock_fifth_child,
    Thermostat.attributes.SystemMode.OFF)})
  test.socket.capability:__expect_send(mock_fifth_child:generate_test_message("main", capabilities.thermostatMode
    .thermostatMode.away()))
  test.socket.zigbee:__queue_receive({mock_fifth_child.id,
                                      Thermostat.attributes.SystemMode:build_test_attr_report(mock_fifth_child,
    Thermostat.attributes.SystemMode.HEAT)})
  test.socket.capability:__expect_send(mock_fifth_child:generate_test_message("main", capabilities.thermostatMode
    .thermostatMode.heat()))
end)

test.register_coroutine_test("ControlSequenceOfOperation reporting should create the appropriate events with fifth child device", function()
  test.socket.zigbee:__queue_receive({mock_fifth_child.id,
                                      Thermostat.attributes.ControlSequenceOfOperation:build_test_attr_report(
    mock_fifth_child, 0x02)})
  test.socket.capability:__expect_send(mock_fifth_child:generate_test_message("main",
    capabilities.thermostatMode.supportedThermostatModes({"away", "heat"}, {
      visibility = {
        displayed = false
      }
    })))
end)

test.register_coroutine_test("OccupiedHeatingSetpoint reporting shoulb create the appropriate events with fifth child device", function()
  test.socket.zigbee:__queue_receive({mock_fifth_child.id,
                                      Thermostat.attributes.OccupiedHeatingSetpoint:build_test_attr_report(mock_fifth_child,
    2100)})
  test.socket.capability:__expect_send(mock_fifth_child:generate_test_message("main",
    capabilities.thermostatHeatingSetpoint.heatingSetpoint({
      value = 21.0,
      unit = "C"
    })))
end)

test.register_coroutine_test("Setting the heating setpoint should generate the appropriate messages with fifth child device", function()
  test.socket.capability:__queue_receive({mock_fifth_child.id, {
    component = "main",
    capability = capabilities.thermostatHeatingSetpoint.ID,
    command = "setHeatingSetpoint",
    args = {21}
  }})
  test.socket.zigbee:__expect_send({mock_device.id,
                                    Thermostat.attributes.OccupiedHeatingSetpoint:write(mock_fifth_child, 2100)})
end)

test.register_coroutine_test("Setting the thermostat mode to away should generate the appropriate messages with fifth child device", function()
  test.socket.capability:__queue_receive({mock_fifth_child.id, {
    component = "main",
    capability = capabilities.thermostatMode.ID,
    command = "setThermostatMode",
    args = {"away"}
  }})
  test.socket.zigbee:__expect_send({mock_device.id,
                                    Thermostat.attributes.SystemMode:write(mock_fifth_child,
    Thermostat.attributes.SystemMode.OFF)})
end)

test.register_coroutine_test("Setting the thermostat mode to heat should generate the appropriate messages with fifth child device", function()
  test.socket.capability:__queue_receive({mock_fifth_child.id, {
    component = "main",
    capability = capabilities.thermostatMode.ID,
    command = "heat",
    args = {}
  }})
  test.socket.zigbee:__expect_send({mock_device.id,
                                    Thermostat.attributes.SystemMode:write(mock_fifth_child,
    Thermostat.attributes.SystemMode.HEAT)})
end)


test.run_registered_tests()
