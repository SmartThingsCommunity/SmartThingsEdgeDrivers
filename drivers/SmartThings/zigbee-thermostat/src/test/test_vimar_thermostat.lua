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
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"
local Thermostat = clusters.Thermostat
local ThermostatMode = capabilities.thermostatMode
local SystemMode = Thermostat.attributes.SystemMode
local ThermostatControlSequence = Thermostat.attributes.ControlSequenceOfOperation

local MAX_VIMAR_THERMOSTAT_HEATPOINT_LIMIT = 39
local MAX_VIMAR_THERMOSTAT_HEATPOINT_LIMIT_ZIGBEE = 3900
local MIN_VIMAR_THERMOSTAT_HEATPOINT_LIMIT = 5
local MIN_VIMAR_THERMOSTAT_HEATPOINT_LIMIT_ZIGBEE = 500
local MAX_VIMAR_THERMOSTAT_COOLPOINT_LIMIT = 40
local MAX_VIMAR_THERMOSTAT_COOLPOINT_LIMIT_ZIGBEE = 4000
local MIN_VIMAR_THERMOSTAT_COOLPOINT_LIMIT = 6
local MIN_VIMAR_THERMOSTAT_COOLPOINT_LIMIT_ZIGBEE = 600

local VIMAR_CURRENT_PROFILE = "_vimarThermostatCurrentProfile"

local VIMAR_THERMOSTAT_HEATING_PROFILE = "thermostat-fanless-heating-no-fw"
local VIMAR_THERMOSTAT_COOLING_PROFILE = "thermostat-fanless-cooling-no-fw"

local mock_device_vimar_heating = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition(VIMAR_THERMOSTAT_HEATING_PROFILE .. ".yml"),
    zigbee_endpoints = {
      [10] = {
        id = 10,
        manufacturer = "Vimar",
        model = "WheelThermostat_v1.0",
        server_clusters = { 0x0000, 0x0003, 0x0201 }
      }
    }
  }
)

local mock_device_vimar_cooling = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition(VIMAR_THERMOSTAT_COOLING_PROFILE .. ".yml"),
    zigbee_endpoints = {
      [10] = {
        id = 10,
        manufacturer = "Vimar",
        model = "WheelThermostat_v1.0",
        server_clusters = { 0x0000, 0x0003, 0x0201 }
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  mock_device_vimar_heating:set_field(VIMAR_CURRENT_PROFILE, ThermostatMode.thermostatMode.heat.NAME, { persist = true })
  mock_device_vimar_cooling:set_field(VIMAR_CURRENT_PROFILE, ThermostatMode.thermostatMode.cool.NAME, { persist = true })
  test.mock_device.add_test_device(mock_device_vimar_heating)
  test.mock_device.add_test_device(mock_device_vimar_cooling)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)


-- Test (Device -> SmartThings)
-- temperatureMeasurement
-- =========================================================
test.register_message_test(
  "Vimar Thermostat - LocalTemperature reporting is handled",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = {
        mock_device_vimar_heating.id,
        Thermostat.attributes.LocalTemperature:build_test_attr_report(mock_device_vimar_heating, 2500)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_vimar_heating:generate_test_message(
        "main",
        capabilities.temperatureMeasurement.temperature({ value = 25.0, unit = "C" })
      )
    }
  }
)

-- Test (Device -> SmartThings)
-- thermostatHeatingSetpoint
-- =========================================================
test.register_message_test(
  "Vimar Thermostat - Heating setpoint reporting should handled",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = {
        mock_device_vimar_heating.id,
        Thermostat.attributes.OccupiedHeatingSetpoint:build_test_attr_report(
          mock_device_vimar_heating,
          3000
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_vimar_heating:generate_test_message(
        "main",
        capabilities.thermostatHeatingSetpoint.heatingSetpoint({ value = 30.0, unit = "C" })
      )
    }
  }
)

-- Test (Device -> SmartThings)
-- thermostatCoolingSetpoint
-- =========================================================
test.register_message_test(
  "Vimar Thermostat - Cooling setpoint reporting should be handled",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = {
        mock_device_vimar_cooling.id,
        Thermostat.attributes.OccupiedCoolingSetpoint:build_test_attr_report(
          mock_device_vimar_cooling,
          1800
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_vimar_cooling:generate_test_message(
        "main",
        capabilities.thermostatCoolingSetpoint.coolingSetpoint({ value = 18.0, unit = "C" })
      )
    }
  }
)

-- Test (SmartThings -> Device)
-- thermostatCoolingSetpoint normal condition
-- =========================================================
test.register_coroutine_test(
  "Vimar Thermostat - Setting cooling setpoint should generate correct zigbee messages",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.capability:__queue_receive(
      {
        mock_device_vimar_cooling.id,
        {
          capability = "thermostatCoolingSetpoint",
          component = "main",
          command = "setCoolingSetpoint",
          args = { 27 }
        }
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device_vimar_cooling.id,
        Thermostat.attributes.OccupiedCoolingSetpoint:write(mock_device_vimar_cooling, 2700)
      }
    )
    test.wait_for_events()

    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send(
      {
        mock_device_vimar_cooling.id,
        Thermostat.attributes.OccupiedCoolingSetpoint:read(mock_device_vimar_cooling)
      }
    )
  end
)

-- Test (SmartThings -> Device)
-- thermostatCoolingSetpoint Fahrenheit conversion
-- =========================================================
test.register_coroutine_test(
  "Vimar Thermostat - Setting cooling setpoint with a Fahrenheit value should generate correct zigbee messages",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.capability:__queue_receive(
      {
        mock_device_vimar_cooling.id,
        {
          capability = "thermostatCoolingSetpoint",
          component = "main",
          command = "setCoolingSetpoint",
          args = { 69 }
        }
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device_vimar_cooling.id,
        Thermostat.attributes.OccupiedCoolingSetpoint:write(mock_device_vimar_cooling, 2056)
      }
    )
    test.wait_for_events()

    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send(
      {
        mock_device_vimar_cooling.id,
        Thermostat.attributes.OccupiedCoolingSetpoint:read(mock_device_vimar_cooling)
      }
    )
  end
)

-- Test (SmartThings -> Device)
-- thermostatCoolingSetpoint MAX limit
-- =========================================================
test.register_coroutine_test(
  "Vimar Thermostat - Setting cooling setpoint at MAX limit should generate correct zigbee messages",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.capability:__queue_receive(
      {
        mock_device_vimar_cooling.id,
        {
          capability = "thermostatCoolingSetpoint",
          component = "main",
          command = "setCoolingSetpoint",
          args = { MAX_VIMAR_THERMOSTAT_COOLPOINT_LIMIT }
        }
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device_vimar_cooling.id,
        Thermostat.attributes.OccupiedCoolingSetpoint:write(
          mock_device_vimar_cooling,
          MAX_VIMAR_THERMOSTAT_COOLPOINT_LIMIT_ZIGBEE
        )
      }
    )
    test.wait_for_events()

    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send(
      {
        mock_device_vimar_cooling.id,
        Thermostat.attributes.OccupiedCoolingSetpoint:read(mock_device_vimar_cooling)
      }
    )
  end
)

-- Test (SmartThings -> Device)
-- thermostatCoolingSetpoint MIN limit
-- =========================================================
test.register_coroutine_test(
  "Vimar Thermostat - Setting cooling setpoint at MIN limit should generate correct zigbee messages",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.capability:__queue_receive(
      {
        mock_device_vimar_cooling.id,
        {
          capability = "thermostatCoolingSetpoint",
          component = "main",
          command = "setCoolingSetpoint",
          args = { MIN_VIMAR_THERMOSTAT_COOLPOINT_LIMIT }
        }
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device_vimar_cooling.id,
        Thermostat.attributes.OccupiedCoolingSetpoint:write(
          mock_device_vimar_cooling,
          MIN_VIMAR_THERMOSTAT_COOLPOINT_LIMIT_ZIGBEE
        )
      }
    )
    test.wait_for_events()

    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send(
      {
        mock_device_vimar_cooling.id,
        Thermostat.attributes.OccupiedCoolingSetpoint:read(mock_device_vimar_cooling)
      }
    )
  end
)


-- Test (SmartThings -> Device)
-- thermostatCoolingSetpoint resolution
-- =========================================================
test.register_coroutine_test(
  "Vimar Thermostat - Setting cooling setpoint with 0.1 resolution should be handled",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_device_vimar_cooling.id,
        {
          capability = "thermostatCoolingSetpoint",
          component = "main",
          command = "setCoolingSetpoint",
          args = { 27.0 }
        }
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device_vimar_cooling.id,
        Thermostat.attributes.OccupiedCoolingSetpoint:write(mock_device_vimar_cooling, 2700)
      }
    )
    test.socket.capability:__queue_receive(
      {
        mock_device_vimar_cooling.id,
        {
          capability = "thermostatCoolingSetpoint",
          component = "main",
          command = "setCoolingSetpoint",
          args = { 27.1 }
        }
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device_vimar_cooling.id,
        Thermostat.attributes.OccupiedCoolingSetpoint:write(mock_device_vimar_cooling, 2710)
      }
    )
    test.socket.capability:__queue_receive(
      {
        mock_device_vimar_cooling.id,
        {
          capability = "thermostatCoolingSetpoint",
          component = "main",
          command = "setCoolingSetpoint",
          args = { 27.2 }
        }
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device_vimar_cooling.id,
        Thermostat.attributes.OccupiedCoolingSetpoint:write(mock_device_vimar_cooling, 2720)
      }
    )
  end
)


-- Test (SmartThings -> Device)
-- thermostatHeatingSetpoint normal condition
-- =========================================================
test.register_coroutine_test(
  "Vimar Thermostat - Setting heating setpoint should generate correct zigbee messages",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.capability:__queue_receive(
      {
        mock_device_vimar_heating.id,
        {
          capability = "thermostatHeatingSetpoint",
          component = "main",
          command = "setHeatingSetpoint",
          args = { 23 }
        }
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device_vimar_heating.id,
        Thermostat.attributes.OccupiedHeatingSetpoint:write(mock_device_vimar_heating, 2300)
      }
    )
    test.wait_for_events()

    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send(
      {
        mock_device_vimar_heating.id,
        Thermostat.attributes.OccupiedHeatingSetpoint:read(mock_device_vimar_heating)
      }
    )
  end
)

-- Test (SmartThings -> Device)
-- thermostatHeatingSetpoint Fahrenheit conversion
-- =========================================================
test.register_coroutine_test(
  "Vimar Thermostat - Setting heating setpoint with a Fahrenheit value should generate correct zigbee messages",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.capability:__queue_receive(
      {
        mock_device_vimar_heating.id,
        {
          capability = "thermostatHeatingSetpoint",
          component = "main",
          command = "setHeatingSetpoint",
          args = { 48 }
        }
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device_vimar_heating.id,
        Thermostat.attributes.OccupiedHeatingSetpoint:write(mock_device_vimar_heating, 889)
      }
    )
    test.wait_for_events()

    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send(
      {
        mock_device_vimar_heating.id,
        Thermostat.attributes.OccupiedHeatingSetpoint:read(mock_device_vimar_heating)
      }
    )
  end
)

-- Test (SmartThings -> Device)
-- thermostatHeatingSetpoint MAX limit
-- =========================================================
test.register_coroutine_test(
  "Vimar Thermostat - Setting heating setpoint at MAX limit should generate correct zigbee messages",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.capability:__queue_receive(
      {
        mock_device_vimar_heating.id,
        {
          capability = "thermostatHeatingSetpoint",
          component = "main",
          command = "setHeatingSetpoint",
          args = { MAX_VIMAR_THERMOSTAT_HEATPOINT_LIMIT }
        }
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device_vimar_heating.id,
        Thermostat.attributes.OccupiedHeatingSetpoint:write(
          mock_device_vimar_heating,
          MAX_VIMAR_THERMOSTAT_HEATPOINT_LIMIT_ZIGBEE
        )
      }
    )
    test.wait_for_events()

    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send(
      {
        mock_device_vimar_heating.id,
        Thermostat.attributes.OccupiedHeatingSetpoint:read(mock_device_vimar_heating)
      }
    )
  end
)

-- Test (SmartThings -> Device)
-- thermostatHeatingSetpoint MIN limit
-- =========================================================
test.register_coroutine_test(
  "Vimar Thermostat - Setting heating setpoint at MIN limit should generate correct zigbee messages",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.capability:__queue_receive(
      {
        mock_device_vimar_heating.id,
        {
          capability = "thermostatHeatingSetpoint",
          component = "main",
          command = "setHeatingSetpoint",
          args = { MIN_VIMAR_THERMOSTAT_HEATPOINT_LIMIT }
        }
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device_vimar_heating.id,
        Thermostat.attributes.OccupiedHeatingSetpoint:write(
          mock_device_vimar_heating,
          MIN_VIMAR_THERMOSTAT_HEATPOINT_LIMIT_ZIGBEE
        )
      }
    )
    test.wait_for_events()

    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send(
      {
        mock_device_vimar_heating.id,
        Thermostat.attributes.OccupiedHeatingSetpoint:read(mock_device_vimar_heating)
      }
    )
  end
)


-- Test (SmartThings -> Device)
-- thermostatHeatingSetpoint resolution
-- =========================================================
test.register_coroutine_test(
  "Vimar Thermostat - Setting heating setpoint with 0.1 resolution should be handled",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_device_vimar_heating.id,
        {
          capability = "thermostatHeatingSetpoint",
          component = "main",
          command = "setHeatingSetpoint",
          args = { 19.0 }
        }
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device_vimar_heating.id,
        Thermostat.attributes.OccupiedHeatingSetpoint:write(mock_device_vimar_heating, 1900)
      }
    )
    test.socket.capability:__queue_receive(
      {
        mock_device_vimar_heating.id,
        {
          capability = "thermostatHeatingSetpoint",
          component = "main",
          command = "setHeatingSetpoint",
          args = { 19.1 }
        }
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device_vimar_heating.id,
        Thermostat.attributes.OccupiedHeatingSetpoint:write(mock_device_vimar_heating, 1910)
      }
    )
    test.socket.capability:__queue_receive(
      {
        mock_device_vimar_heating.id,
        {
          capability = "thermostatHeatingSetpoint",
          component = "main",
          command = "setHeatingSetpoint",
          args = { 19.2 }
        }
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device_vimar_heating.id,
        Thermostat.attributes.OccupiedHeatingSetpoint:write(mock_device_vimar_heating, 1920)
      }
    )
  end
)


-- Test (Device -> SmartThings)
-- Cooling Only
-- =========================================================
test.register_message_test(
  "Vimar Thermostat - ControlSequenceOfOperation reporting (CoolingOnly) is handled",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = {
        mock_device_vimar_heating.id,
        Thermostat.attributes.ControlSequenceOfOperation:build_test_attr_report(
          mock_device_vimar_heating,
          ThermostatControlSequence.COOLING_ONLY
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_vimar_heating:generate_test_message(
        "main",
        capabilities.thermostatMode.supportedThermostatModes(
          { ThermostatMode.thermostatMode.off.NAME, ThermostatMode.thermostatMode.cool.NAME },
          { visibility = { displayed = false } }
        )
      )
    }
  }
)

-- Test (Device -> SmartThings)
-- Heating Only
-- =========================================================
test.register_message_test(
  "Vimar Thermostat - ControlSequenceOfOperation reporting (HeatingOnly) is handled",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = {
        mock_device_vimar_heating.id,
        Thermostat.attributes.ControlSequenceOfOperation:build_test_attr_report(
          mock_device_vimar_heating,
          ThermostatControlSequence.HEATING_ONLY
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_vimar_heating:generate_test_message(
        "main",
        capabilities.thermostatMode.supportedThermostatModes(
          { ThermostatMode.thermostatMode.off.NAME, ThermostatMode.thermostatMode.heat.NAME },
          { visibility = { displayed = false } }
        )
      )
    }
  }
)

-- Test (SmartThings -> Device)
-- Refresh
-- =========================================================
test.register_message_test(
  "Vimar Thermostat - Refresh capability should read all required attributes in heating mode",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { mock_device_vimar_heating.id,
        { capability = "refresh", component = "main", command = "refresh", args = {} } }
    },
    -- [NOTE:] Strict order
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device_vimar_heating.id,
        Thermostat.attributes.LocalTemperature:read(mock_device_vimar_heating)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device_vimar_heating.id,
        Thermostat.attributes.ControlSequenceOfOperation:read(mock_device_vimar_heating)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device_vimar_heating.id,
        Thermostat.attributes.ThermostatRunningState:read(mock_device_vimar_heating)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device_vimar_heating.id,
        Thermostat.attributes.SystemMode:read(mock_device_vimar_heating)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device_vimar_heating.id,
        Thermostat.attributes.OccupiedHeatingSetpoint:read(mock_device_vimar_heating)
      }
    }
  }
)


-- Test (SmartThings -> Device)
-- Refresh
-- =========================================================
test.register_message_test(
  "Vimar Thermostat - Refresh capability should read all required attributes in cooling mode",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { mock_device_vimar_cooling.id,
        { capability = "refresh", component = "main", command = "refresh", args = {} } }
    },
    -- [NOTE:] Strict order
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device_vimar_cooling.id,
        Thermostat.attributes.LocalTemperature:read(mock_device_vimar_cooling)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device_vimar_cooling.id,
        Thermostat.attributes.ControlSequenceOfOperation:read(mock_device_vimar_cooling)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device_vimar_cooling.id,
        Thermostat.attributes.ThermostatRunningState:read(mock_device_vimar_cooling)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device_vimar_cooling.id,
        Thermostat.attributes.SystemMode:read(mock_device_vimar_cooling)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device_vimar_cooling.id,
        Thermostat.attributes.OccupiedCoolingSetpoint:read(mock_device_vimar_cooling)
      }
    }
  }
)

-- Test (Device -> SmartThings)
-- SystemMode
-- =========================================================
test.register_coroutine_test(
  "Vimar Thermostat - Thermostat mode (Cool --> Heat) changed using the physical button is handled",
  function()
    test.socket.zigbee:__queue_receive(
      {
        mock_device_vimar_cooling.id,
        Thermostat.attributes.SystemMode:build_test_attr_report(mock_device_vimar_cooling, SystemMode.HEAT)
      }
    )
    mock_device_vimar_cooling:expect_metadata_update({ profile = VIMAR_THERMOSTAT_HEATING_PROFILE })
    test.socket.capability:__expect_send(
      {
        mock_device_vimar_cooling.id,
        {
          capability_id = "thermostatMode",
          component_id = "main",
          attribute_id = "thermostatMode",
          state = { value = "heat" }
        }
      }
    )
  end
)

-- Test (Device -> SmartThings)
-- SystemMode
-- =========================================================
test.register_coroutine_test(
  "Vimar Thermostat - Thermostat mode changed (Heat --> Cool) using the physical button is handled",
  function()
    test.socket.zigbee:__queue_receive(
      {
        mock_device_vimar_heating.id,
        Thermostat.attributes.SystemMode:build_test_attr_report(mock_device_vimar_heating, SystemMode.COOL)
      }
    )
    mock_device_vimar_heating:expect_metadata_update({ profile = VIMAR_THERMOSTAT_COOLING_PROFILE })
    test.socket.capability:__expect_send(
      {
        mock_device_vimar_heating.id,
        {
          capability_id = "thermostatMode",
          component_id = "main",
          attribute_id = "thermostatMode",
          state = { value = "cool" }
        }
      }
    )
  end
)

test.run_registered_tests()
