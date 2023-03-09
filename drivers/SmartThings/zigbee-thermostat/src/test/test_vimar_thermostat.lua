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
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"
local Thermostat = clusters.Thermostat
local ThermostatMode = capabilities.thermostatMode
local ThermostatControlSequence = Thermostat.attributes.ControlSequenceOfOperation

local MAX_VIMAR_THERMOSTAT_HEATPOINT_LIMIT = 38
local MAX_VIMAR_THERMOSTAT_HEATPOINT_LIMIT_ZIGBEE = 3800
local MIN_VIMAR_THERMOSTAT_HEATPOINT_LIMIT = 6
local MIN_VIMAR_THERMOSTAT_HEATPOINT_LIMIT_ZIGBEE = 600
local MAX_VIMAR_THERMOSTAT_COOLPOINT_LIMIT = 38
local MAX_VIMAR_THERMOSTAT_COOLPOINT_LIMIT_ZIGBEE = 3800
local MIN_VIMAR_THERMOSTAT_COOLPOINT_LIMIT = 6
local MIN_VIMAR_THERMOSTAT_COOLPOINT_LIMIT_ZIGBEE = 600

local mock_device_vimar = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("thermostat-fanless-heating-cooling-no-fw.yml"),
    zigbee_endpoints = {
      [10] = {
        id = 10,
        manufacturer = "Vimar",
        model = "WheelThermostat_v1.0",
        server_clusters = {0x0000, 0x0003, 0x0201}
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device_vimar)
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
          mock_device_vimar.id, 
          Thermostat.attributes.LocalTemperature:build_test_attr_report(mock_device_vimar,2500) 
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device_vimar:generate_test_message(
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
          mock_device_vimar.id, 
          Thermostat.attributes.OccupiedHeatingSetpoint:build_test_attr_report(
            mock_device_vimar,
            3000
          ) 
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device_vimar:generate_test_message(
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
          mock_device_vimar.id, 
          Thermostat.attributes.OccupiedCoolingSetpoint:build_test_attr_report(
            mock_device_vimar,
            1800
          ) 
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device_vimar:generate_test_message(
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
            mock_device_vimar.id,
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
            mock_device_vimar.id,
            Thermostat.attributes.OccupiedCoolingSetpoint:write(mock_device_vimar, 2700)
          }
      )
      test.wait_for_events()

      test.mock_time.advance_time(2)
      test.socket.zigbee:__expect_send(
          {
            mock_device_vimar.id,
            Thermostat.attributes.OccupiedCoolingSetpoint:read(mock_device_vimar)
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
            mock_device_vimar.id,
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
            mock_device_vimar.id,
            Thermostat.attributes.OccupiedCoolingSetpoint:write(mock_device_vimar, 2056)
          }
      )
      test.wait_for_events()

      test.mock_time.advance_time(2)
      test.socket.zigbee:__expect_send(
          {
            mock_device_vimar.id,
            Thermostat.attributes.OccupiedCoolingSetpoint:read(mock_device_vimar)
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
            mock_device_vimar.id,
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
            mock_device_vimar.id,
            Thermostat.attributes.OccupiedCoolingSetpoint:write(
              mock_device_vimar, 
              MAX_VIMAR_THERMOSTAT_COOLPOINT_LIMIT_ZIGBEE
            )
          }
      )
      test.wait_for_events()

      test.mock_time.advance_time(2)
      test.socket.zigbee:__expect_send(
          {
            mock_device_vimar.id,
            Thermostat.attributes.OccupiedCoolingSetpoint:read(mock_device_vimar)
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
            mock_device_vimar.id,
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
            mock_device_vimar.id,
            Thermostat.attributes.OccupiedCoolingSetpoint:write(
              mock_device_vimar, 
              MIN_VIMAR_THERMOSTAT_COOLPOINT_LIMIT_ZIGBEE
            )
          }
      )
      test.wait_for_events()

      test.mock_time.advance_time(2)
      test.socket.zigbee:__expect_send(
          {
            mock_device_vimar.id,
            Thermostat.attributes.OccupiedCoolingSetpoint:read(mock_device_vimar)
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
            mock_device_vimar.id,
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
            mock_device_vimar.id,
            Thermostat.attributes.OccupiedHeatingSetpoint:write(mock_device_vimar, 2300)
          }
      )
      test.wait_for_events()

      test.mock_time.advance_time(2)
      test.socket.zigbee:__expect_send(
          {
            mock_device_vimar.id,
            Thermostat.attributes.OccupiedHeatingSetpoint:read(mock_device_vimar)
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
            mock_device_vimar.id,
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
            mock_device_vimar.id,
            Thermostat.attributes.OccupiedHeatingSetpoint:write(mock_device_vimar, 889)
          }
      )
      test.wait_for_events()

      test.mock_time.advance_time(2)
      test.socket.zigbee:__expect_send(
          {
            mock_device_vimar.id,
            Thermostat.attributes.OccupiedHeatingSetpoint:read(mock_device_vimar)
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
            mock_device_vimar.id,
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
            mock_device_vimar.id,
            Thermostat.attributes.OccupiedHeatingSetpoint:write(
              mock_device_vimar, 
              MAX_VIMAR_THERMOSTAT_HEATPOINT_LIMIT_ZIGBEE
            )
          }
      )
      test.wait_for_events()

      test.mock_time.advance_time(2)
      test.socket.zigbee:__expect_send(
          {
            mock_device_vimar.id,
            Thermostat.attributes.OccupiedHeatingSetpoint:read(mock_device_vimar)
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
            mock_device_vimar.id,
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
            mock_device_vimar.id,
            Thermostat.attributes.OccupiedHeatingSetpoint:write(
              mock_device_vimar, 
              MIN_VIMAR_THERMOSTAT_HEATPOINT_LIMIT_ZIGBEE
            )
          }
      )
      test.wait_for_events()

      test.mock_time.advance_time(2)
      test.socket.zigbee:__expect_send(
          {
            mock_device_vimar.id,
            Thermostat.attributes.OccupiedHeatingSetpoint:read(mock_device_vimar)
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
          mock_device_vimar.id, 
          Thermostat.attributes.ControlSequenceOfOperation:build_test_attr_report(
            mock_device_vimar, 
            ThermostatControlSequence.COOLING_ONLY
          ) 
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device_vimar:generate_test_message(
          "main", 
          capabilities.thermostatMode.supportedThermostatModes(
          { ThermostatMode.thermostatMode.off.NAME, ThermostatMode.thermostatMode.cool.NAME},
          { visibility = { displayed = false }}
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
          mock_device_vimar.id, 
          Thermostat.attributes.ControlSequenceOfOperation:build_test_attr_report(
            mock_device_vimar, 
            ThermostatControlSequence.HEATING_ONLY
          ) 
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device_vimar:generate_test_message(
          "main", 
          capabilities.thermostatMode.supportedThermostatModes(
          { ThermostatMode.thermostatMode.off.NAME, ThermostatMode.thermostatMode.heat.NAME },
          { visibility = { displayed = false }}
        )
        )
      }
    }
)

-- Test (SmartThings -> Device) 
-- Refresh
-- =========================================================
test.register_message_test(
  "Vimar Thermostat - Refresh capability should read all required attributes",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { mock_device_vimar.id, {capability = "refresh", component = "main", command = "refresh", args = {}}}
    },
    -- [NOTE:] Strict order
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device_vimar.id,
        Thermostat.attributes.LocalTemperature:read(mock_device_vimar)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device_vimar.id,
        Thermostat.attributes.OccupiedHeatingSetpoint:read(mock_device_vimar)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device_vimar.id,
        Thermostat.attributes.OccupiedCoolingSetpoint:read(mock_device_vimar)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device_vimar.id,
        Thermostat.attributes.ControlSequenceOfOperation:read(mock_device_vimar)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device_vimar.id,
        Thermostat.attributes.ThermostatRunningState:read(mock_device_vimar)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device_vimar.id,
        Thermostat.attributes.SystemMode:read(mock_device_vimar)
      }
    },
  }
)


test.run_registered_tests()