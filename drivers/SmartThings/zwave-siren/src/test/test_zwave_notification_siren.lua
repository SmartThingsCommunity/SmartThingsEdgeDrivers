-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local test = require "integration_test"
local capabilities = require "st.capabilities"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local Notification = (require "st.zwave.CommandClass.Notification")({version=3})
local t_utils = require "integration_test.utils"

-- supported comand classes: NOTIFIATION
local siren_notification_endpoints = {
  {
    command_classes = {
      {value = zw.NOTIFICATION}
    }
  }
}

local mock_siren_notification = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("base-siren.yml"),
  zwave_endpoints = siren_notification_endpoints
})

local function test_init()
  test.mock_device.add_test_device(mock_siren_notification)
end
test.set_test_init_function(test_init)

test.register_message_test(
    "Notification report siren type IDLE_STATE should be handled as alarm off, swtich off",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_siren_notification.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
          notification_type = Notification.notification_type.SIREN,
          event = Notification.event.siren.IDLE_STATE
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_siren_notification:generate_test_message("main", capabilities.alarm.alarm.off())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_siren_notification:generate_test_message("main", capabilities.switch.switch.off())
      }
    }
)

test.register_message_test(
    "Notification report siren type ACTIVE should be handled as siren both, swtich on",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_siren_notification.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
          notification_type = Notification.notification_type.SIREN,
          event = Notification.event.siren.ACTIVE
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_siren_notification:generate_test_message("main", capabilities.alarm.alarm.both())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_siren_notification:generate_test_message("main", capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
    "Notification report home security type STATE_IDLE should be handled as tamper alert clear",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_siren_notification.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
          notification_type = Notification.notification_type.HOME_SECURITY,
          event = Notification.event.home_security.STATE_IDLE
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_siren_notification:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
      }
    }
)

test.register_message_test(
    "Notification report home security type TAMPERING_PRODUCT_COVER_REMOVED should be handled as tamper alert detected, siren both",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_siren_notification.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
          notification_type = Notification.notification_type.HOME_SECURITY,
          event = Notification.event.home_security.TAMPERING_PRODUCT_COVER_REMOVED
        })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_siren_notification:generate_test_message("main", capabilities.alarm.alarm.both())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_siren_notification:generate_test_message("main", capabilities.tamperAlert.tamper.detected())
      }
    }
)

test.run_registered_tests()
