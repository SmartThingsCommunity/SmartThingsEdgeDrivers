-- Copyright 2022 SmartThings
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
local clusters = require "st.zigbee.zcl.clusters"
local Thermostat = clusters.Thermostat
local FanControl = clusters.FanControl
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"
local capabilities = require "st.capabilities"

local mock_device = test.mock_device.build_test_zigbee_device(
  { profile = t_utils.get_profile_definition("base-thermostat.yml"),
    zigbee_endpoints = {
      [10] = {
        id = 10,
        manufacturer = "HAI",
        model = "65A01-1",
        server_clusters = {0x0201, 0x0204, 0x0202, 0x0003}
      }
    }
  }
)

local ENDPOINT = 10

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Configure should configure all necessary attributes",
  function ()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({mock_device.id, "doConfigure"})
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Thermostat.attributes.SystemMode:configure_reporting(mock_device, 5, 1800, nil):to_endpoint(ENDPOINT)})
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Thermostat.attributes.OccupiedCoolingSetpoint:configure_reporting(mock_device, 5, 1800, 100):to_endpoint(ENDPOINT)})
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Thermostat.attributes.OccupiedHeatingSetpoint:configure_reporting(mock_device, 5, 1800, 100):to_endpoint(ENDPOINT)})
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Thermostat.attributes.LocalTemperature:configure_reporting(mock_device, 5, 1800, 100):to_endpoint(ENDPOINT)})
    test.socket.zigbee:__expect_send({
      mock_device.id,
      FanControl.attributes.FanMode:configure_reporting(mock_device, 5, 1800, nil):to_endpoint(ENDPOINT)})
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_coroutine_test(
  "Refresh should read all necessary attributes",
  function ()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.capability:__queue_receive( {mock_device.id, { capability = "refresh", component = "main", command = "refresh", args = {} }} )
    test.socket.zigbee:__expect_send( { mock_device.id, FanControl.attributes.FanMode:read(mock_device):to_endpoint(ENDPOINT) })
    test.socket.zigbee:__expect_send( { mock_device.id, Thermostat.attributes.SystemMode:read(mock_device):to_endpoint(ENDPOINT) })
    test.socket.zigbee:__expect_send( { mock_device.id, Thermostat.attributes.ControlSequenceOfOperation:read(mock_device):to_endpoint(ENDPOINT) })
    test.socket.zigbee:__expect_send( { mock_device.id, Thermostat.attributes.OccupiedCoolingSetpoint:read(mock_device):to_endpoint(ENDPOINT) })
    test.socket.zigbee:__expect_send( { mock_device.id, Thermostat.attributes.OccupiedHeatingSetpoint:read(mock_device):to_endpoint(ENDPOINT) })
    test.socket.zigbee:__expect_send( { mock_device.id, Thermostat.attributes.LocalTemperature:read(mock_device):to_endpoint(ENDPOINT) })
  end
)

test.register_coroutine_test(
  "Temperature reporting should create the appropriate events",
  function ()
    test.socket.zigbee:__queue_receive({ mock_device.id, Thermostat.attributes.LocalTemperature:build_test_attr_report(mock_device, 2100) })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({value = 21.0, unit = "C"})))
  end
)

test.register_coroutine_test(
  "Thermostat mode reporting should create the appropriate events",
  function ()
    test.socket.zigbee:__queue_receive({ mock_device.id, Thermostat.attributes.SystemMode:build_test_attr_report(mock_device, Thermostat.attributes.SystemMode.OFF) })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.thermostatMode.thermostatMode.off()))
  end
)

test.register_coroutine_test(
  -- This thermostat uses a non-standard supported mode mapping
  "ControlSequenceOfOperation reporting should create the appropriate events",
  function ()
    test.socket.zigbee:__queue_receive({ mock_device.id, Thermostat.attributes.ControlSequenceOfOperation:build_test_attr_report(mock_device, 0x02)})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.thermostatMode.supportedThermostatModes({"auto", "cool", "heat", "emergency heat"},{visibility = {displayed = false }})))
  end
)

test.register_coroutine_test(
  "Thermostat fan mode reporting should create the appropriate events",
  function ()
    test.socket.zigbee:__queue_receive({ mock_device.id, FanControl.attributes.FanMode:build_test_attr_report(mock_device, FanControl.attributes.FanMode.AUTO) })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.thermostatFanMode.thermostatFanMode.auto()))
  end
)

test.register_coroutine_test(
  "Thermostat cooling setpoint reporting should create the appropriate events if the mode is supported",
  function ()
    test.socket.zigbee:__queue_receive({ mock_device.id, Thermostat.attributes.ControlSequenceOfOperation:build_test_attr_report(mock_device, 0x00)})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.thermostatMode.supportedThermostatModes({"auto", "cool", "heat", "emergency heat"},{visibility = {displayed = false }})))
    test.socket.zigbee:__queue_receive({ mock_device.id, Thermostat.attributes.SystemMode:build_test_attr_report(mock_device, Thermostat.attributes.SystemMode.COOL)})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.thermostatMode.thermostatMode.cool()))
    test.socket.zigbee:__queue_receive({ mock_device.id, Thermostat.attributes.OccupiedCoolingSetpoint:build_test_attr_report(mock_device, 2100) })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.thermostatCoolingSetpoint.coolingSetpoint({value = 21.0, unit = "C"})))
  end
)

test.register_coroutine_test(
  "Thermostat heating setpoint reporting should create the appropriate events if the mode is supported",
  function ()
    test.socket.zigbee:__queue_receive({ mock_device.id, Thermostat.attributes.ControlSequenceOfOperation:build_test_attr_report(mock_device, 0x02)})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.thermostatMode.supportedThermostatModes({"auto", "cool", "heat", "emergency heat"},{visibility = {displayed = false }})))
    test.socket.zigbee:__queue_receive({ mock_device.id, Thermostat.attributes.SystemMode:build_test_attr_report(mock_device, Thermostat.attributes.SystemMode.EMERGENCY_HEATING)})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.thermostatMode.thermostatMode.emergency_heat()))
    test.socket.zigbee:__queue_receive({ mock_device.id, Thermostat.attributes.OccupiedHeatingSetpoint:build_test_attr_report(mock_device, 2100) })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.thermostatHeatingSetpoint.heatingSetpoint({value = 21.0, unit = "C"})))
  end
)

test.register_coroutine_test(
  "Thermostat heating setpoint reporting should not create setpoint events if the mode is not currently active",
  function ()
    test.socket.zigbee:__queue_receive({ mock_device.id, Thermostat.attributes.ControlSequenceOfOperation:build_test_attr_report(mock_device, 0x00)})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.thermostatMode.supportedThermostatModes({"auto", "cool", "heat", "emergency heat"},{visibility = {displayed = false }})))
    test.socket.zigbee:__queue_receive({ mock_device.id, Thermostat.attributes.SystemMode:build_test_attr_report(mock_device, Thermostat.attributes.SystemMode.COOL)})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.thermostatMode.thermostatMode.cool()))
    test.socket.zigbee:__queue_receive({ mock_device.id, Thermostat.attributes.OccupiedHeatingSetpoint:build_test_attr_report(mock_device, 2100) })
  end
)

test.register_coroutine_test(
  "Thermostat cooling setpoint reporting should not create setpoint events if the mode is not currently active",
  function ()
    test.socket.zigbee:__queue_receive({ mock_device.id, Thermostat.attributes.ControlSequenceOfOperation:build_test_attr_report(mock_device, 0x02)})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.thermostatMode.supportedThermostatModes({"auto", "cool", "heat", "emergency heat"},{visibility = {displayed = false }})))
    test.socket.zigbee:__queue_receive({ mock_device.id, Thermostat.attributes.SystemMode:build_test_attr_report(mock_device, Thermostat.attributes.SystemMode.EMERGENCY_HEATING)})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.thermostatMode.thermostatMode.emergency_heat()))
    test.socket.zigbee:__queue_receive({ mock_device.id, Thermostat.attributes.OccupiedCoolingSetpoint:build_test_attr_report(mock_device, 2100) })
  end
)

test.register_coroutine_test(
  "Setting the heating setpoint should generate the appropriate messages",
  function ()
    test.socket.capability:__queue_receive({ mock_device.id, { component = "main", capability = capabilities.thermostatHeatingSetpoint.ID, command = "setHeatingSetpoint", args = {21} } })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.thermostatHeatingSetpoint.heatingSetpoint({value = 21.0, unit = "C"})))
    test.socket.zigbee:__expect_send( { mock_device.id, Thermostat.attributes.OccupiedHeatingSetpoint:write(mock_device, 2100):to_endpoint(ENDPOINT) })
  end
)

test.register_coroutine_test(
  "Setting the cooling setpoint should generate the appropriate messages",
  function ()
    test.socket.capability:__queue_receive({ mock_device.id, { component = "main", capability = capabilities.thermostatCoolingSetpoint.ID, command = "setCoolingSetpoint", args = {21} } })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.thermostatCoolingSetpoint.coolingSetpoint({value = 21.0, unit = "C"})))
    test.socket.zigbee:__expect_send( { mock_device.id, Thermostat.attributes.OccupiedCoolingSetpoint:write(mock_device, 2100):to_endpoint(ENDPOINT) })
  end
)

test.register_coroutine_test(
  "Setting the thermostat mode should generate the appropriate messages",
  function ()
    test.socket.capability:__queue_receive({ mock_device.id, { component = "main", capability = capabilities.thermostatMode.ID, command = "setThermostatMode", args = {"cool"} } })
    test.socket.zigbee:__expect_send( { mock_device.id, Thermostat.attributes.SystemMode:write(mock_device, 3):to_endpoint(ENDPOINT) })
  end
)

test.register_coroutine_test(
  "Setting the thermostat fan mode should generate the appropriate messages",
  function ()
    test.socket.capability:__queue_receive({ mock_device.id, { component = "main", capability = capabilities.thermostatFanMode.ID, command = "setThermostatFanMode", args = {"auto"} } })
    test.socket.zigbee:__expect_send( { mock_device.id, FanControl.attributes.FanMode:write(mock_device, 5):to_endpoint(ENDPOINT) })
  end
)

test.run_registered_tests()
