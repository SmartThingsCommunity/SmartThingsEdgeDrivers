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
local capabilities = require "st.capabilities"
local zw_test_utilities = require "integration_test.zwave_test_utils"
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 2 })
local ThermostatMode = (require "st.zwave.CommandClass.ThermostatMode")({ version = 2 })
local ThermostatSetpoint = (require "st.zwave.CommandClass.ThermostatSetpoint")({ version = 1 })
local zw = require "st.zwave"
local t_utils = require "integration_test.utils"

-- supported comand classes
local thermostat_endpoints = {
  {
    command_classes = {
      {value = zw.BATTERY},
      {value = zw.THERMOSTAT_MODE},
      {value = zw.THERMOSTAT_SETPOINT},
      {value = zw.SENSOR_MULTILEVEL},
    }
  }
}

local mock_device = test.mock_device.build_test_zwave_device(
  {
    profile = t_utils.get_profile_definition("base-radiator-thermostat.yml"),
    zwave_endpoints = thermostat_endpoints,
    zwave_manufacturer_id = 0x0371,
    zwave_product_id = 0x0015,
    zwave_product_type = 0x0002,
  }
)
local function test_init()
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

test.register_message_test(
    "Refresh Capability Command should refresh Thermostat device",
    {
      {
        channel = "capability",
        direction = "receive",
        message = {
          mock_device.id,
          { capability = "refresh", command = "refresh", args = {} }
        }
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utilities.zwave_test_build_send_command(
          mock_device,
          ThermostatMode:Get({})
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utilities.zwave_test_build_send_command(
          mock_device,
          SensorMultilevel:Get({})
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utilities.zwave_test_build_send_command(
          mock_device,
          ThermostatSetpoint:Get({setpoint_type = 1})
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utilities.zwave_test_build_send_command(
          mock_device,
          Battery:Get({})
        )
      },
      --
    },
    {
      inner_block_ordering = "relaxed"
    }
)

test.register_message_test(
    "Battery report should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utilities.zwave_test_build_receive_command(Battery:Report({ battery_level = 0x63 })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.battery.battery(99))
      }
    }
)

test.register_message_test(
    "Low battery report should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utilities.zwave_test_build_receive_command(Battery:Report({ battery_level = 0xFF })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.battery.battery(1))
      }
    }
)

test.register_message_test(
    "Celsius temperature reports should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id,
                    zw_test_utilities.zwave_test_build_receive_command(SensorMultilevel:Report({
                                                                                                 sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
                                                                                                 scale = 0,
                                                                                                 sensor_value = 21.5 })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 21.5, unit = 'C' }))
      }
    }
)

test.register_message_test(
    "Thermostat mode reports should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id,
                    zw_test_utilities.zwave_test_build_receive_command(ThermostatMode:Report({ mode = ThermostatMode.mode.HEAT })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.thermostatMode.thermostatMode({ value = "heat" }))
      }
    }
)

test.register_message_test(
    "Heating setpoint reports should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id,
                    zw_test_utilities.zwave_test_build_receive_command(ThermostatSetpoint:Report({
                                                                                                   setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1,
                                                                                                   scale = 0,
                                                                                                   value = 21.5 })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.thermostatHeatingSetpoint.heatingSetpoint({ value = 21.5, unit = 'C' }))
      }
    }
)

test.register_coroutine_test(
    "Setting the thermostat mode should generate the appropriate commands",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive({ mock_device.id, { capability = "thermostatMode", command = "setThermostatMode", args = { "heat" } } })
      test.socket.zwave:__expect_send(
          zw_test_utilities.zwave_test_build_send_command(
              mock_device,
              ThermostatMode:Set({
                                   mode = ThermostatMode.mode.HEAT
                                 })
          )
      )
      test.wait_for_events()

      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(
          zw_test_utilities.zwave_test_build_send_command(
              mock_device,
              ThermostatMode:Get({})
          )
      )
    end
)

test.register_coroutine_test(
    "Setting the heating setpoint should generate the appropriate commands",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive({ mock_device.id, { capability = "thermostatHeatingSetpoint", command = "setHeatingSetpoint", args = { 21.5 } } })
      test.socket.zwave:__expect_send(
          zw_test_utilities.zwave_test_build_send_command(
              mock_device,
              ThermostatSetpoint:Set({
                                       setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1,
                                       value = 21.5,
                                       precision = 1,
                                       size = 2
                                     })
          )
      )
      test.wait_for_events()

      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(
          zw_test_utilities.zwave_test_build_send_command(
              mock_device,
              ThermostatSetpoint:Get({
                                       setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1
                                     })
          )
      )
    end
)

test.run_registered_tests()
