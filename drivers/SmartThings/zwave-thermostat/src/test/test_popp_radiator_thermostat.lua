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
local ThermostatSetpoint = (require "st.zwave.CommandClass.ThermostatSetpoint")({ version = 1 })
local WakeUp = (require "st.zwave.CommandClass.WakeUp")({ version = 2})
local zw = require "st.zwave"
local t_utils = require "integration_test.utils"

-- supported comand classes
local thermostat_endpoints = {
  {
    command_classes = {
      {value = zw.BATTERY},
      {value = zw.THERMOSTAT_SETPOINT},
      {value = zw.SENSOR_MULTILEVEL},
    }
  }
}

local mock_device = test.mock_device.build_test_zwave_device(
  {
    profile = t_utils.get_profile_definition("popp-radiator-thermostat.yml"),
    zwave_endpoints = thermostat_endpoints,
    zwave_manufacturer_id = 0x0002,
    zwave_product_id = 0xA010,
    zwave_product_type = 0x0115
  }
)
local function test_init()
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

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
      },
      {
        channel = "devices",
        direction = "send",
        message = {
        "register_native_capability_attr_handler",
        { device_uuid = mock_device.id, capability_id = "temperatureMeasurement", capability_attr_id = "temperature" }
      }
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
    "Setting the heating setpoint should generate the appropriate commands",
    function()
      mock_device:set_field("latest_wakeup", 0, {persist = true})
      test.timer.__create_and_queue_test_time_advance_timer(200, "oneshot")
      local setpoint_value = 21.5
      test.socket.capability:__queue_receive({ mock_device.id, { capability = "thermostatHeatingSetpoint", command = "setHeatingSetpoint", args = { setpoint_value } } })
      test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.thermostatHeatingSetpoint.heatingSetpoint({ value = setpoint_value, unit = "C" })))

      test.wait_for_events()
      test.socket.zwave:__queue_receive({mock_device.id, WakeUp:Notification({})})
      test.socket.zwave:__expect_send(
        zw_test_utilities.zwave_test_build_send_command(
          mock_device,
          WakeUp:IntervalGet({}))
      )

      test.mock_time.advance_time(200)
    end
)

test.register_coroutine_test(
    "Setting the heating setpoint should generate the appropriate commands",
    function()
      mock_device:set_field("latest_wakeup", 0, {persist = true})
      test.timer.__create_and_queue_test_time_advance_timer(590, "oneshot")
      local setpoint_value = 21.5
      local setCommand = ThermostatSetpoint:Set({
        setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1,
        value = setpoint_value,
        scale = ThermostatSetpoint.scale.CELSIUS
      })

      test.socket.capability:__queue_receive({ mock_device.id, { capability = "thermostatHeatingSetpoint", command = "setHeatingSetpoint", args = { setpoint_value } } })

      test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.thermostatHeatingSetpoint.heatingSetpoint({ value = setpoint_value, unit = "C" })))

      test.wait_for_events()

      test.socket.zwave:__queue_receive({mock_device.id, WakeUp:Notification({}) })
      test.socket.zwave:__expect_send(
        zw_test_utilities.zwave_test_build_send_command(
          mock_device,
          WakeUp:IntervalGet({}))
      )

      test.mock_time.advance_time(590)

      test.socket.zwave:__expect_send(
        zw_test_utilities.zwave_test_build_send_command(
          mock_device,
          setCommand)
      )

      test.socket.zwave:__expect_send(
        zw_test_utilities.zwave_test_build_send_command(
          mock_device,
          ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1}))
      )
    end
)

test.run_registered_tests()
