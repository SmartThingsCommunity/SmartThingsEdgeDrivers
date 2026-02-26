-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local t_utils = require "integration_test.utils"
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local cluster_base = require "st.zigbee.cluster_base"
local utils = require "st.utils"

-- Device endpoints with supported clusters
local inovelli_vzm31_sn_endpoints = {
  [1] = {
    id = 1,
    manufacturer = "Inovelli",
    model = "VZM31-SN",
    server_clusters = {0x0006, 0x0008, 0x0300} -- OnOff, Level, ColorControl
  }
}

local mock_parent_device = test.mock_device.build_test_zigbee_device({
  profile = t_utils.get_profile_definition("inovelli-vzm31-sn.yml"),
  zigbee_endpoints = inovelli_vzm31_sn_endpoints,
  fingerprinted_endpoint_id = 0x01
})

zigbee_test_utils.prepare_zigbee_env_info()

local mock_child_device = test.mock_device.build_test_child_device({
  profile = t_utils.get_profile_definition("rgbw-bulb.yml"),
  parent_device_id = mock_parent_device.id,
  parent_assigned_child_key = "notification"
})

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
      message = mock_child_device:generate_test_message("main", capabilities.colorTemperature.colorTemperature(6500))
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

    test.socket.zigbee:__expect_send({
      mock_parent_device.id,
      cluster_base.build_manufacturer_specific_command(
        mock_parent_device,
        0xFC31, -- PRIVATE_CLUSTER_ID
        0x01,   -- PRIVATE_CMD_NOTIF_ID
        0x122F, -- MFG_CODE
        utils.serialize_int(notificationValue, 4, false, false)
      )
    })
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

    test.socket.zigbee:__expect_send({
      mock_parent_device.id,
      cluster_base.build_manufacturer_specific_command(
        mock_parent_device,
        0xFC31, -- PRIVATE_CLUSTER_ID
        0x01,   -- PRIVATE_CMD_NOTIF_ID
        0x122F, -- MFG_CODE
        utils.serialize_int(0, 4, false, false)
      )
    })
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

    test.socket.zigbee:__expect_send({
      mock_parent_device.id,
      cluster_base.build_manufacturer_specific_command(
        mock_parent_device,
        0xFC31, -- PRIVATE_CLUSTER_ID
        0x01,   -- PRIVATE_CMD_NOTIF_ID
        0x122F, -- MFG_CODE
        utils.serialize_int(notificationValue, 4, false, false)
      )
    })
  end,
  {
     min_api_version = 19
  }
)

-- Test child device color command
test.register_coroutine_test(
  "Child device color command should emit events and send configuration to parent",
  function()
    local color = math.random(0, 100)
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

    test.socket.zigbee:__expect_send({
      mock_parent_device.id,
      cluster_base.build_manufacturer_specific_command(
        mock_parent_device,
        0xFC31, -- PRIVATE_CLUSTER_ID
        0x01,   -- PRIVATE_CMD_NOTIF_ID
        0x122F, -- MFG_CODE
        utils.serialize_int(notificationValue, 4, false, false)
      )
    })
  end,
  {
     min_api_version = 19
  }
)

-- Test child device color temperature command
test.register_coroutine_test(
  "Child device color temperature command should emit events and send configuration to parent",
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
      { capability = "colorTemperature", command = "setColorTemperature", args = { 3000 } }
    })

    test.socket.capability:__expect_send(
      mock_child_device:generate_test_message("main", capabilities.colorControl.hue(100))
    )

    test.socket.capability:__expect_send(
      mock_child_device:generate_test_message("main", capabilities.colorTemperature.colorTemperature(3000))
    )

    test.socket.capability:__expect_send(
      mock_child_device:generate_test_message("main", capabilities.switch.switch("on"))
    )

    test.wait_for_events()
    test.mock_time.advance_time(1)

    test.socket.zigbee:__expect_send({
      mock_parent_device.id,
      cluster_base.build_manufacturer_specific_command(
        mock_parent_device,
        0xFC31, -- PRIVATE_CLUSTER_ID
        0x01,   -- PRIVATE_CMD_NOTIF_ID
        0x122F, -- MFG_CODE
        utils.serialize_int(notificationValue, 4, false, false)
      )
    })
  end,
  {
     min_api_version = 19
  }
)

test.run_registered_tests()

