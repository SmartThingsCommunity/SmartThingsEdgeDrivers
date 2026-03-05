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
local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
local zw_test_utils = require "integration_test.zwave_test_utils"
local t_utils = require "integration_test.utils"
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 4 })

local sensor_endpoints = {
  {
    command_classes = {
      {value = cc.BASIC},
      {value = cc.NOTIFICATION},
      {value = cc.BATTERY},
    }
  }
}

local mock_device = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("contact-battery-tamperalert.yml"),
  zwave_endpoints = sensor_endpoints,
  zwave_manufacturer_id = 0x014F,
  zwave_product_type = 0x2001,
  zwave_product_id = 0x0102,
})

local function test_init()
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

test.register_message_test(
  "Notification report with v1 alarm level set to 7 should be handled (closed)",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(
        Notification:Report({
          event=Notification.event.home_security.INTRUSION,
          notification_status=0xFF,
          notification_type=Notification.notification_type.HOME_SECURITY,
          v1_alarm_level=0,
          v1_alarm_type=7,
        })
      ) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.contactSensor.contact.closed())
    }
  }
)

test.register_message_test(
  "Notification report with v1 alarm level set to 7 should be handled (open)",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(
        Notification:Report({
          event=Notification.event.home_security.UNKNOWN_EVENT_STATE,
          notification_status=0xFF,
          notification_type=Notification.notification_type.HOME_SECURITY,
          v1_alarm_level=0xFF,
          v1_alarm_type=7,
        })
      ) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.contactSensor.contact.open())
    }
  }
)

test.register_coroutine_test(
  "Notification report with v1 alarm level set to 7 should be handled (tamper)",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(10, "oneshot")
    test.socket.zwave:__queue_receive({mock_device.id, Notification:Report({
      event=Notification.event.home_security.TAMPERING_PRODUCT_COVER_REMOVED,
      notification_status=0xFF,
      notification_type=Notification.notification_type.HOME_SECURITY,
      v1_alarm_level=0xFF,
      v1_alarm_type=7,
    })})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.tamperAlert.tamper.detected()))
    test.mock_time.advance_time(10)
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.tamperAlert.tamper.clear()))
  end
)

test.run_registered_tests()
