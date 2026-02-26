-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local Configuration = (require "st.zwave.CommandClass.Configuration")({version=4})
local t_utils = require "integration_test.utils"
local st_device = require "st.device"

-- Inovelli VZW32-SN device identifiers
local INOVELLI_MANUFACTURER_ID = 0x031E
local INOVELLI_VZW32_SN_PRODUCT_TYPE = 0x0017
local INOVELLI_VZW32_SN_PRODUCT_ID = 0x0001

-- Device endpoints with supported command classes
local inovelli_vzw32_sn_endpoints = {
  {
    command_classes = {
      {value = zw.SWITCH_BINARY},
      {value = zw.SWITCH_MULTILEVEL},
      {value = zw.BASIC},
      {value = zw.CONFIGURATION},
      {value = zw.CENTRAL_SCENE},
      {value = zw.ASSOCIATION},
    }
  }
}

-- Create mock parent device
local mock_parent_device = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("inovelli-mmwave-dimmer-vzw32-sn.yml"),
  zwave_endpoints = inovelli_vzw32_sn_endpoints,
  zwave_manufacturer_id = INOVELLI_MANUFACTURER_ID,
  zwave_product_type = INOVELLI_VZW32_SN_PRODUCT_TYPE,
  zwave_product_id = INOVELLI_VZW32_SN_PRODUCT_ID
})

-- Create mock child device (notification device)
local mock_child_device = test.mock_device.build_test_child_device({
  profile = t_utils.get_profile_definition("rgbw-bulb.yml"),
  parent_device_id = mock_parent_device.id,
  parent_assigned_child_key = "notification"
})

-- Set child device network type
mock_child_device.network_type = st_device.NETWORK_TYPE_CHILD

local function test_init()
  test.mock_device.add_test_device(mock_parent_device)
  test.mock_device.add_test_device(mock_child_device)
end
test.set_test_init_function(test_init)

-- Test child device initialization
test.register_message_test(
  "Child device should initialize with default color values",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_child_device.id, "added" },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_child_device:generate_test_message("main", capabilities.colorControl.hue(1))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_child_device:generate_test_message("main", capabilities.colorControl.saturation(1))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_child_device:generate_test_message("main", capabilities.colorTemperature.colorTemperatureRange({ value = {minimum = 2700, maximum = 6500} }))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_child_device:generate_test_message("main", capabilities.switchLevel.level(100))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_child_device:generate_test_message("main", capabilities.switch.switch("off"))
    },
  },
  {
    inner_block_ordering = "relaxed"
  },
  {
     min_api_version = 19
  }
)

-- Test child device switch on command
test.register_coroutine_test(
  "Child device switch on should emit events and send configuration to parent",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")

    -- Calculate expected configuration value using the same logic as getNotificationValue
    local function huePercentToValue(value)
      if value <= 2 then
        return 0
      elseif value >= 98 then
        return 255
      else
        return math.floor(value / 100 * 255 + 0.5) -- utils.round equivalent
      end
    end

    local notificationValue = 0
    local level = 100 -- Default level for child devices
    local color = 100 -- Default color for child devices (since device starts with no hue state)
    local effect = 1 -- Default notificationType

    notificationValue = notificationValue + (effect * 16777216)
    notificationValue = notificationValue + (huePercentToValue(color) * 65536)
    notificationValue = notificationValue + (level * 256)
    notificationValue = notificationValue + (255 * 1)

    test.socket.capability:__queue_receive({
      mock_child_device.id,
      { capability = "switch", command = "on", args = {} }
    })

    test.socket.capability:__expect_send(
      mock_child_device:generate_test_message("main", capabilities.switch.switch("on"))
    )

    test.wait_for_events()
    test.mock_time.advance_time(1)

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent_device,
        Configuration:Set({
          parameter_number = 99,
          configuration_value = notificationValue,
          size = 4
        })
      )
    )
  end,
  {
     min_api_version = 19
  }
)

-- Test child device switch off command
test.register_coroutine_test(
  "Child device switch off should emit events and send configuration to parent",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")

    test.socket.capability:__queue_receive({
      mock_child_device.id,
      { capability = "switch", command = "off", args = {} }
    })

    test.socket.capability:__expect_send(
      mock_child_device:generate_test_message("main", capabilities.switch.switch("off"))
    )

    test.wait_for_events()
    test.mock_time.advance_time(1)

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent_device,
        Configuration:Set({
          parameter_number = 99,
          configuration_value = 0, -- Switch off sends 0
          size = 4
        })
      )
    )
  end,
  {
     min_api_version = 19
  }
)

-- Test child device level command
test.register_coroutine_test(
  "Child device level command should emit events and send configuration to parent",
  function()
    local level = math.random(1, 99)
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")

    -- Calculate expected configuration value using the same logic as getNotificationValue
    local function huePercentToValue(value)
      if value <= 2 then
        return 0
      elseif value >= 98 then
        return 255
      else
        return math.floor(value / 100 * 255 + 0.5) -- utils.round equivalent
      end
    end

    local notificationValue = 0
    local effect = 1 -- Default notificationType
    local color = 100 -- Default color for child devices (since device starts with no hue state)

    notificationValue = notificationValue + (effect * 16777216)
    notificationValue = notificationValue + (huePercentToValue(color) * 65536)
    notificationValue = notificationValue + (level * 256) -- Use the actual level from command
    notificationValue = notificationValue + (255 * 1)

    test.socket.capability:__queue_receive({
      mock_child_device.id,
      { capability = "switchLevel", command = "setLevel", args = { level } }
    })

    test.socket.capability:__expect_send(
      mock_child_device:generate_test_message("main", capabilities.switchLevel.level(level))
    )

    test.socket.capability:__expect_send(
      mock_child_device:generate_test_message("main", capabilities.switch.switch("on"))
    )

    test.wait_for_events()
    test.mock_time.advance_time(1)

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent_device,
        Configuration:Set({
          parameter_number = 99,
          configuration_value = notificationValue,
          size = 4
        })
      )
    )
  end,
  {
     min_api_version = 19
  }
)

-- Test child device color command
test.register_coroutine_test(
  "Child device color command should emit events and send configuration to parent",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")

    -- Calculate expected configuration value using the same logic as getNotificationValue
    local function huePercentToValue(value)
      if value <= 2 then
        return 0
      elseif value >= 98 then
        return 255
      else
        return math.floor(value / 100 * 255 + 0.5) -- utils.round equivalent
      end
    end

    local notificationValue = 0
    local level = 100 -- Default level for child devices
    local color = math.random(0, 100) -- Default color for child devices (since device starts with no hue state)
    local effect = 1 -- Default notificationType

    notificationValue = notificationValue + (effect * 16777216)
    notificationValue = notificationValue + (huePercentToValue(color) * 65536)
    notificationValue = notificationValue + (level * 256)
    notificationValue = notificationValue + (255 * 1)

    test.socket.capability:__queue_receive({
      mock_child_device.id,
      { capability = "colorControl", command = "setColor", args = {{ hue = color, saturation = 100 }} }
    })

    test.socket.capability:__expect_send(
      mock_child_device:generate_test_message("main", capabilities.colorControl.hue(color))
    )

    test.socket.capability:__expect_send(
      mock_child_device:generate_test_message("main", capabilities.colorControl.saturation(100))
    )

    test.socket.capability:__expect_send(
      mock_child_device:generate_test_message("main", capabilities.switch.switch("on"))
    )

    test.wait_for_events()
    test.mock_time.advance_time(1)

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent_device,
        Configuration:Set({
          parameter_number = 99,
          configuration_value = notificationValue,
          size = 4
        })
      )
    )
  end,
  {
     min_api_version = 19
  }
)

-- Test child device color temperature command
test.register_coroutine_test(
  "Child device color temperature command should emit events and send configuration to parent",
  function()
    local temp = math.random(2700, 6500)
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")

    test.socket.capability:__queue_receive({
      mock_child_device.id,
      { capability = "colorTemperature", command = "setColorTemperature", args = { temp } }
    })

    test.socket.capability:__expect_send(
      mock_child_device:generate_test_message("main", capabilities.colorControl.hue(100))
    )

    test.socket.capability:__expect_send(
      mock_child_device:generate_test_message("main", capabilities.colorTemperature.colorTemperature(temp))
    )

    test.socket.capability:__expect_send(
      mock_child_device:generate_test_message("main", capabilities.switch.switch("on"))
    )

    test.wait_for_events()
    test.mock_time.advance_time(1)

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent_device,
        Configuration:Set({
          parameter_number = 99,
          configuration_value = 33514751, -- Calculated: effect(1)*16777216 + hue(255)*65536 + level(100)*256 + 255
          size = 4
        })
      )
    )
  end,
  {
     min_api_version = 19
  }
)

test.run_registered_tests()
