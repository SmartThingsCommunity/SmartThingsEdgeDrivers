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
local Basic = (require "st.zwave.CommandClass.Basic")({version=1})
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({version=5})
local Notification = (require "st.zwave.CommandClass.Notification")({version=3})
local t_utils = require "integration_test.utils"

local siren_endpoints = {
    {
      command_classes = {
        {value = zw.NOTIFICATION},
        {value = zw.SENSOR_MULTILEVEL}
      }
    }
  }

--- {mfr = 0x027A, prod = 0x000C, model = 0x0003} Zooz S2 Multisiren ZSE19
local mock_siren = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("multifunctional-siren.yml"),
  zwave_endpoints = siren_endpoints,
  zwave_manufacturer_id = 0x027A,
  zwave_product_type = 0x000C,
  zwave_product_id = 0x0003,
})

local function test_init()
  test.mock_device.add_test_device(mock_siren)
end

test.set_test_init_function(test_init)

test.register_message_test(
    "Basic report 0x00 should be handled as alarm off, swtich off",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
            mock_siren.id,
            zw_test_utils.zwave_test_build_receive_command(Basic:Report({ value = 0 })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_siren:generate_test_message("main", capabilities.alarm.alarm.off())
      }
    }
)

test.register_message_test(
    "Notification report home security type TAMPERING_PRODUCT_COVER_REMOVED should be handled as tamper alert detected",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_siren.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
          notification_type = Notification.notification_type.HOME_SECURITY,
          event = Notification.event.home_security.TAMPERING_PRODUCT_COVER_REMOVED
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_siren:generate_test_message("main", capabilities.tamperAlert.tamper.detected())
      }
    }
)

test.register_message_test(
    "SensorMultilevel report relative humidity type should be handled as humidity",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_siren.id, zw_test_utils.zwave_test_build_receive_command(SensorMultilevel:Report({
          sensor_type = SensorMultilevel.sensor_type.RELATIVE_HUMIDITY,
          sensor_value = 25
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_siren:generate_test_message("main", capabilities.relativeHumidityMeasurement.humidity({value = 25}))
      }
    }
)

test.register_message_test(
  "SensorMultilevel report temperature type should be handled as temperature",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_siren.id, zw_test_utils.zwave_test_build_receive_command(SensorMultilevel:Report({
          sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
          sensor_value = 25
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_siren:generate_test_message("main", capabilities.temperatureMeasurement.temperature({value = 25, unit = 'C'}))
      }
    }
)

test.register_coroutine_test(
  "doConfigure lifecycle event should generate proper commands",
  function()
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_siren.id, "doConfigure" })
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.TEMPERATURE})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_siren,
      SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.RELATIVE_HUMIDITY})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_siren,
      Notification:Get({notification_type = Notification.notification_type.HOME_SECURITY})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_siren,
      Basic:Get({})
    ))
    mock_siren:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.run_registered_tests()
