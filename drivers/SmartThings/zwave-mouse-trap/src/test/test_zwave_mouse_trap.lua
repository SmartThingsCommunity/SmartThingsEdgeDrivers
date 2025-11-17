-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local test = require "integration_test"
local capabilities = require "st.capabilities"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 4 })
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })
local WakeUp = (require "st.zwave.CommandClass.WakeUp")({ version = 1 })
local t_utils = require "integration_test.utils"

local DOME_MANUFACTURER_ID = 0x021F
local DOME_MOUSE_TRAP_PRODUCT_TYPE = 0x0003
local DOME_MOUSE_TRAP_PRODUCT_ID = 0x0104

local mouse_trap_endpoints = {
  {
    command_classes = {
      {value = zw.NOTIFICATION},
      {value = zw.BATTERY},
      {value = zw.WAKEUP}
    }
  }
}

local mock_mouse_trap = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("pest-control-battery.yml"),
  zwave_endpoints = mouse_trap_endpoints,
  zwave_manufacturer_id = DOME_MANUFACTURER_ID,
  zwave_product_type = DOME_MOUSE_TRAP_PRODUCT_TYPE,
  zwave_product_id = DOME_MOUSE_TRAP_PRODUCT_ID
})

local function test_init()
  test.mock_device.add_test_device(mock_mouse_trap)
end
test.set_test_init_function(test_init)

test.register_message_test(
  "Notification report should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_mouse_trap.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
        notification_type = Notification.notification_type.HOME_SECURITY,
        event = Notification.event.home_security.MOTION_DETECTION_LOCATION_PROVIDED
      })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_mouse_trap:generate_test_message("main", capabilities.pestControl.pestControl.pestExterminated())
    }
  }
)

test.register_message_test(
  "Notification report should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_mouse_trap.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
        notification_type = Notification.notification_type.HOME_SECURITY,
        event = Notification.event.home_security.STATE_IDLE
      })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_mouse_trap:generate_test_message("main", capabilities.pestControl.pestControl.idle())
    }
  }
)

test.register_message_test(
  "Notification report should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_mouse_trap.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
        notification_type = Notification.notification_type.PEST_CONTROL,
        event = Notification.event.pest_control.TRAP_ARMED
      })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_mouse_trap:generate_test_message("main", capabilities.pestControl.pestControl.trapArmed())
    }
  }
)

test.register_message_test(
  "Notification report should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_mouse_trap.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
        notification_type = Notification.notification_type.PEST_CONTROL,
        event = Notification.event.pest_control.TRAP_ARMED_LOCATION_PROVIDED
      })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_mouse_trap:generate_test_message("main", capabilities.pestControl.pestControl.trapArmed())
    }
  }
)

test.register_message_test(
  "Notification report should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_mouse_trap.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
        notification_type = Notification.notification_type.PEST_CONTROL,
        event = Notification.event.pest_control.TRAP_RE_ARM_REQUIRED
      })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_mouse_trap:generate_test_message("main", capabilities.pestControl.pestControl.trapRearmRequired())
    }
  }
)

test.register_message_test(
  "Notification report should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_mouse_trap.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
        notification_type = Notification.notification_type.PEST_CONTROL,
        event = Notification.event.pest_control.PEST_DETECTED
      })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_mouse_trap:generate_test_message("main", capabilities.pestControl.pestControl.pestDetected())
    }
  }
)

test.register_message_test(
  "Notification report should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_mouse_trap.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
        notification_type = Notification.notification_type.PEST_CONTROL,
        event = Notification.event.pest_control.PEST_DETECTED_LOCATION_PROVIDED
      })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_mouse_trap:generate_test_message("main", capabilities.pestControl.pestControl.pestDetected())
    }
  }
)

test.register_message_test(
  "Notification report should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_mouse_trap.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
        notification_type = Notification.notification_type.PEST_CONTROL,
        event = Notification.event.pest_control.PEST_EXTERMINATED
      })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_mouse_trap:generate_test_message("main", capabilities.pestControl.pestControl.pestExterminated())
    }
  }
)

test.register_message_test(
  "Notification report should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_mouse_trap.id, zw_test_utils.zwave_test_build_receive_command(Notification:Report({
        notification_type = Notification.notification_type.PEST_CONTROL,
        event = Notification.event.pest_control.UNKNOWN_EVENT_STATE
      })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_mouse_trap:generate_test_message("main", capabilities.pestControl.pestControl.idle())
    }
  }
)

test.register_message_test(
  "Battery percentage report should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_mouse_trap.id, zw_test_utils.zwave_test_build_receive_command(Battery:Report({battery_level=0x55})) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_mouse_trap:generate_test_message("main", capabilities.battery.battery(85))
    }
  }
)

test.register_message_test(
  "Low battery report should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_mouse_trap.id, zw_test_utils.zwave_test_build_receive_command(Battery:Report({ battery_level = 0xFF })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_mouse_trap:generate_test_message("main", capabilities.battery.battery(1))
    }
  }
)

test.register_coroutine_test(
    "Device should be configured",
    function()
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({mock_mouse_trap.id, "doConfigure"})
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_mouse_trap,
        Notification:Get({ notification_type = Notification.notification_type.PEST_CONTROL})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_mouse_trap,
        WakeUp:IntervalSet({node_id = 0x00, seconds = 43200})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_mouse_trap,
        Battery:Get({})
      ))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_mouse_trap,
          Configuration:Set({parameter_number=1, configuration_value=255, size=2})
        )
      )
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_mouse_trap,
          Configuration:Set({parameter_number=2, configuration_value=2, size=1})
        )
      )
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_mouse_trap,
          Configuration:Set({parameter_number=3, configuration_value=360, size=2})
        )
      )
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_mouse_trap,
          Configuration:Set({parameter_number=4, configuration_value=1, size=1})
        )
      )
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_mouse_trap,
          Configuration:Set({parameter_number=5, configuration_value=0, size=1})
        )
      )
      mock_mouse_trap:expect_metadata_update({provisioning_state = "PROVISIONED"})
    end
)

test.run_registered_tests()
