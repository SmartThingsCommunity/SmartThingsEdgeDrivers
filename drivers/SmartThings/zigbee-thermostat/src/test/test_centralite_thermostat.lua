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

-- Mock out globals
local test = require "integration_test"
local clusters = require "st.zigbee.zcl.clusters"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"

local capabilities = require "st.capabilities"

local Thermostat = clusters.Thermostat

local mock_device = test.mock_device.build_test_zigbee_device(
    {
      profile = t_utils.get_profile_definition("base-thermostat-no-operating-state.yml"),
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "Centralite",
          model = "3157100",
          server_clusters = { 0x0000, 0x0001, 0x0003, 0x0020, 0x0201, 0x0202, 0x0204, 0x0B05},
          client_clusters = {0x000A, 0x0019}
        }
      }
    }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

test.register_message_test(
   "Temperature reports using the thermostat cluster should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, Thermostat.attributes.LocalTemperature:build_test_attr_report(mock_device,
                                                                                                  2500) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 25.0, unit = "C" }))
      }
    }
)

test.register_message_test(
    "Heating setpoint reports are handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, Thermostat.attributes.OccupiedHeatingSetpoint:build_test_attr_report(mock_device,
                                                                                                         2500) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.thermostatHeatingSetpoint.heatingSetpoint({ value = 25.0, unit = "C" }))
      }
    }
)

test.register_message_test(
    "Cooling setpoint reports are handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, Thermostat.attributes.OccupiedCoolingSetpoint:build_test_attr_report(mock_device,
                                                                                                         2500) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.thermostatCoolingSetpoint.coolingSetpoint({ value = 25.0, unit = "C" }))
      }
    }
)

test.register_coroutine_test(
    "Setting thermostat cooling setpoint should generate correct zigbee messages",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_device.id,
            { capability = "thermostatCoolingSetpoint", component = "main", command = "setCoolingSetpoint", args = { 27 } }
          }
      )
      test.socket.zigbee:__expect_send(
          {
            mock_device.id,
            Thermostat.attributes.OccupiedCoolingSetpoint:write(mock_device, 2700)
          }
      )
      test.wait_for_events()

      test.mock_time.advance_time(2)
      test.socket.zigbee:__expect_send(
          {
            mock_device.id,
            Thermostat.attributes.OccupiedCoolingSetpoint:read(mock_device)
          }
      )
    end
)

test.register_coroutine_test(
    "Setting thermostat cooling setpoint with a fahrenheit value should generate correct zigbee messages",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_device.id,
            { capability = "thermostatCoolingSetpoint", component = "main", command = "setCoolingSetpoint", args = { 78 } }
          }
      )
      test.socket.zigbee:__expect_send(
          {
            mock_device.id,
            Thermostat.attributes.OccupiedCoolingSetpoint:write(mock_device, 2556)
          }
      )
      test.wait_for_events()

      test.mock_time.advance_time(2)
      test.socket.zigbee:__expect_send(
          {
            mock_device.id,
            Thermostat.attributes.OccupiedCoolingSetpoint:read(mock_device)
          }
      )
    end
)

test.run_registered_tests()
