-- Copyright 2021 SmartThings
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
local t_utils = require "integration_test.utils"

local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })
local Alarm = (require "st.zwave.CommandClass.Alarm")({ version = 1, strict = true })

-- supported comand classes
local sensor_endpoints = {
  {
    command_classes = {
      {value = zw.ALARM},
    }
  }
}

local mock_device = test.mock_device.build_test_zwave_device(
  {
    profile = t_utils.get_profile_definition("smoke-co-battery.yml"),
    zwave_endpoints = sensor_endpoints,
    -- First Alert Smoke Detector
    zwave_manufacturer_id = 0x0138,
    zwave_product_type = 0x0001,
    zwave_product_id = 0x0002
  }
)

local function  test_init()
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

test.register_message_test(
    "Alarm report (smoke detected) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Alarm:Report({
          alarm_type = Alarm.z_wave_alarm_type.SMOKE,
          alarm_level = 1
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.smokeDetector.smoke.detected())
      }
    }
)

test.register_message_test(
    "Alarm report (smoke clear) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Alarm:Report({
          alarm_type = Alarm.z_wave_alarm_type.SMOKE,
          alarm_level = 0
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.smokeDetector.smoke.clear())
      }
    }
)

test.register_message_test(
    "Alarm report (CO detected) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Alarm:Report({
          alarm_type = Alarm.z_wave_alarm_type.CO,
          alarm_level = 1
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.carbonMonoxideDetector.carbonMonoxide.detected())
      }
    }
)

test.register_message_test(
    "Alarm report (CO clear) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Alarm:Report({
          alarm_type = Alarm.z_wave_alarm_type.CO,
          alarm_level = 0
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.carbonMonoxideDetector.carbonMonoxide.clear())
      }
    }
)

test.register_message_test(
    "Alarm custom value 12 should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Alarm:Report({
          alarm_type = 12,
          alarm_level = 0
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.smokeDetector.smoke.tested())
      }
    }
)

test.register_message_test(
    "Alarm custom value 13 should generate Clear Capability event",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Alarm:Report({
          alarm_type = 13,
          alarm_level = 0
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.smokeDetector.smoke.clear())
      }
    }
)

test.register_message_test(
    "Notification report (smoke) should be re-directed to default handler",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
          notification_type = Notification.notification_type.SMOKE,
          event = Notification.event.smoke.DETECTED_LOCATION_PROVIDED
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.smokeDetector.smoke.detected())
      }
    }
)

test.run_registered_tests()
