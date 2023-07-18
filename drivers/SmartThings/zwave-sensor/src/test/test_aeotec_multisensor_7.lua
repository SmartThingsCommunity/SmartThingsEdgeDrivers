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
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 1 })
local Association = (require "st.zwave.CommandClass.Association")({ version = 2 })
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })
local SensorBinary = (require "st.zwave.CommandClass.SensorBinary")({ version = 2 })
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 5 })
local WakeUp = (require "st.zwave.CommandClass.WakeUp")({ version = 2 })
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
local t_utils = require "integration_test.utils"

local sensor_endpoints = {
  {
    command_classes = {
      {value = zw.ASSOCIATION},
      {value = zw.BATTERY},
      {value = zw.CONFIGURATION},
      {value = zw.NOTIFICATION},
      {value = zw.SENSOR_BINARY},
      {value = zw.SENSOR_MULTILEVEL},
      {value = zw.WAKE_UP}
    }
  }
}

local mock_sensor = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("aeotec-multisensor-7.yml"),
  zwave_endpoints = sensor_endpoints,
  zwave_manufacturer_id = 0x0371,
  zwave_product_type = 0x0102,
  zwave_product_id = 0x0018,
})

local function test_init()
  test.mock_device.add_test_device(mock_sensor)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
    "doConfigure lifecycle event should generate the correct commands",
    function ()
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({ mock_sensor.id, "doConfigure" })
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Association:Set({ grouping_identifier = 1, node_ids = {} })
      ))

      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Configuration:Set({ parameter_number = 101, configuration_value = -16, size = 1 })
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Configuration:Set({ parameter_number = 102, configuration_value = 1, size = 1 })
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Configuration:Set({ parameter_number = 3, configuration_value = 30, size = 2 })
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Configuration:Set({ parameter_number = 4, configuration_value = 11, size = 1 })
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Configuration:Set({ parameter_number = 111, configuration_value = 8*60, size = 2 })
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Configuration:Set({ parameter_number = 112, configuration_value = 6*60*60, size = 2 })
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Configuration:Set({ parameter_number = 40, configuration_value = 1, size = 1 })
      ))

      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          SensorBinary:Get({sensor_type = SensorBinary.sensor_type.MOTION})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Battery:Get({})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.TEMPERATURE})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.LUMINANCE, scale = SensorMultilevel.scale.luminance.LUX})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.RELATIVE_HUMIDITY})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.ULTRAVIOLET})
      ))

      mock_sensor:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
)

test.register_coroutine_test(
    "Wakeup notification should generate the correct commands",
    function ()
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.zwave:__queue_receive(
        {
          mock_sensor.id,
          WakeUp:Notification({})
        }
      )
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_sensor,
        WakeUp:IntervalGet({})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Configuration:Get({parameter_number = 10})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          SensorBinary:Get({sensor_type = SensorBinary.sensor_type.MOTION})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Battery:Get({})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.TEMPERATURE})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.LUMINANCE, scale = SensorMultilevel.scale.luminance.LUX})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.RELATIVE_HUMIDITY})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.ULTRAVIOLET})
      ))

      end
)
test.register_coroutine_test(
    "Configuration value should be updated and device refreshed, when wakeup notification received",
    function()
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle():__queue_receive({mock_sensor.id, "init"})
      test.socket.device_lifecycle():__queue_receive(mock_sensor:generate_info_changed(
          {
              preferences = {
                motionDelayTime = 120,
                motionSensitivity = 3,
                reportInterval = 1800
              }
          }
      ))
      test.wait_for_events()
      test.socket.zwave:__queue_receive(
        {
          mock_sensor.id,
          WakeUp:Notification({})
        }
      )
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Configuration:Get({parameter_number = 10})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_sensor,
        WakeUp:IntervalGet({})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Configuration:Set({parameter_number = 3, size = 2, configuration_value = 120})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Configuration:Set({parameter_number = 4, size = 1, configuration_value = 3})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Configuration:Set({parameter_number = 111, size = 2, configuration_value = 1800})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          SensorBinary:Get({sensor_type = SensorBinary.sensor_type.MOTION})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Battery:Get({})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.TEMPERATURE})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.LUMINANCE, scale = SensorMultilevel.scale.luminance.LUX})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.RELATIVE_HUMIDITY})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.ULTRAVIOLET})
      ))
    end
)

test.register_message_test(
  "SensorMultilevel report ultraviolet type should be handled as ultravioletIndex",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_sensor.id, zw_test_utils.zwave_test_build_receive_command(SensorMultilevel:Report({
          sensor_type = SensorMultilevel.sensor_type.ULTRAVIOLET,
          sensor_value = 10
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_sensor:generate_test_message("main", capabilities.ultravioletIndex.ultravioletIndex({value = 10}))
      }
    }
)

test.register_message_test(
    "Notification reports about power management should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_sensor.id,
          Notification:Report({notification_type = Notification.notification_type.POWER_MANAGEMENT, event = Notification.event.power_management.AC_MAINS_DISCONNECTED})
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_sensor:generate_test_message("main", capabilities.powerSource.powerSource.battery())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_sensor.id,
          Notification:Report({notification_type = Notification.notification_type.POWER_MANAGEMENT, event = Notification.event.power_management.AC_MAINS_RE_CONNECTED})
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_sensor:generate_test_message("main", capabilities.powerSource.powerSource.dc())
      }
    }
)

test.register_message_test(
    "Configuration reports about power management should be handled",
    {
    {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_sensor.id,
          Configuration:Report({parameter_number = 10, configuration_value = 1})
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_sensor:generate_test_message("main", capabilities.powerSource.powerSource.dc())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_sensor.id,
          Configuration:Report({parameter_number = 10, configuration_value = 0})
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_sensor:generate_test_message("main", capabilities.powerSource.powerSource.battery())
      }
    }
)

test.run_registered_tests()
