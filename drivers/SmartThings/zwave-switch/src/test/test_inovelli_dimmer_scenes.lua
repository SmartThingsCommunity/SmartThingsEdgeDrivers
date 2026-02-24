-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local t_utils = require "integration_test.utils"
local CentralScene = (require "st.zwave.CommandClass.CentralScene")({version=1})

local INOVELLI_MANUFACTURER_ID = 0x031E
local INOVELLI_LZW31_PRODUCT_TYPE = 0x0001
local INOVELLI_DIMMER_PRODUCT_ID = 0x0001

local BUTTON_UP_SCENE_2 = 2
local BUTTON_DOWN_SCENE_1 = 1
local BUTTON_CONFIGURE_SCENE_3 = 3

local inovelli_dimmer_endpoints = {
  {
    command_classes = {
      { value = zw.BASIC },
      { value = zw.SWITCH_MULTILEVEL },
      { value = zw.METER },
      { value = zw.CENTRAL_SCENE }
    }
  }
}

local mock_inovelli_dimmer = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("inovelli-dimmer-power-energy.yml"),
  zwave_endpoints = inovelli_dimmer_endpoints,
  zwave_manufacturer_id = INOVELLI_MANUFACTURER_ID,
  zwave_product_type = INOVELLI_LZW31_PRODUCT_TYPE,
  zwave_product_id = INOVELLI_DIMMER_PRODUCT_ID
})

local function test_init()
  test.mock_device.add_test_device(mock_inovelli_dimmer)
end
test.set_test_init_function(test_init)

test.register_message_test(
  "Central Scene notification Button held should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_inovelli_dimmer.id, zw_test_utils.zwave_test_build_receive_command(CentralScene:Notification({
        scene_number = BUTTON_UP_SCENE_2,
        key_attributes=CentralScene.key_attributes.KEY_PRESSED_1_TIME}))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_inovelli_dimmer:generate_test_message("button2", capabilities.button.button.pushed({
        state_change = true }))
    }
  }
)

test.register_message_test(
  "Central Scene notification Button held should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_inovelli_dimmer.id, zw_test_utils.zwave_test_build_receive_command(CentralScene:Notification({
        scene_number = BUTTON_UP_SCENE_2,
        key_attributes=CentralScene.key_attributes.KEY_PRESSED_2_TIMES}))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_inovelli_dimmer:generate_test_message("button2", capabilities.button.button.pushed_2x({
        state_change = true }))
    }
  }
)

test.register_message_test(
  "Central Scene notification Button held should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_inovelli_dimmer.id, zw_test_utils.zwave_test_build_receive_command(CentralScene:Notification({
        scene_number = BUTTON_UP_SCENE_2,
        key_attributes=CentralScene.key_attributes.KEY_PRESSED_3_TIMES}))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_inovelli_dimmer:generate_test_message("button2", capabilities.button.button.pushed_3x({
        state_change = true }))
    }
  }
)

test.register_message_test(
  "Central Scene notification Button held should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_inovelli_dimmer.id, zw_test_utils.zwave_test_build_receive_command(CentralScene:Notification({
        scene_number = BUTTON_UP_SCENE_2,
        key_attributes=CentralScene.key_attributes.KEY_PRESSED_4_TIMES}))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_inovelli_dimmer:generate_test_message("button2", capabilities.button.button.pushed_4x({
        state_change = true }))
    }
  }
)

test.register_message_test(
  "Central Scene notification Button held should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_inovelli_dimmer.id, zw_test_utils.zwave_test_build_receive_command(CentralScene:Notification({
        scene_number = BUTTON_UP_SCENE_2,
        key_attributes=CentralScene.key_attributes.KEY_PRESSED_5_TIMES}))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_inovelli_dimmer:generate_test_message("button2", capabilities.button.button.pushed_5x({
        state_change = true }))
    }
  }
)

test.register_message_test(
  "Central Scene notification Button held should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_inovelli_dimmer.id, zw_test_utils.zwave_test_build_receive_command(CentralScene:Notification({
        scene_number = BUTTON_DOWN_SCENE_1,
        key_attributes=CentralScene.key_attributes.KEY_PRESSED_1_TIME}))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_inovelli_dimmer:generate_test_message("button1", capabilities.button.button.pushed({
        state_change = true }))
    }
  }
)

test.register_message_test(
  "Central Scene notification Button held should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_inovelli_dimmer.id, zw_test_utils.zwave_test_build_receive_command(CentralScene:Notification({
        scene_number = BUTTON_DOWN_SCENE_1,
        key_attributes=CentralScene.key_attributes.KEY_PRESSED_2_TIMES}))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_inovelli_dimmer:generate_test_message("button1", capabilities.button.button.pushed_2x({
        state_change = true }))
    }
  }
)

test.register_message_test(
  "Central Scene notification Button held should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_inovelli_dimmer.id, zw_test_utils.zwave_test_build_receive_command(CentralScene:Notification({
        scene_number = BUTTON_DOWN_SCENE_1,
        key_attributes=CentralScene.key_attributes.KEY_PRESSED_3_TIMES}))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_inovelli_dimmer:generate_test_message("button1", capabilities.button.button.pushed_3x({
        state_change = true }))
    }
  }
)

test.register_message_test(
  "Central Scene notification Button held should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_inovelli_dimmer.id, zw_test_utils.zwave_test_build_receive_command(CentralScene:Notification({
        scene_number = BUTTON_DOWN_SCENE_1,
        key_attributes=CentralScene.key_attributes.KEY_PRESSED_4_TIMES}))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_inovelli_dimmer:generate_test_message("button1", capabilities.button.button.pushed_4x({
        state_change = true }))
    }
  }
)

test.register_message_test(
  "Central Scene notification Button held should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_inovelli_dimmer.id, zw_test_utils.zwave_test_build_receive_command(CentralScene:Notification({
        scene_number = BUTTON_DOWN_SCENE_1,
        key_attributes=CentralScene.key_attributes.KEY_PRESSED_5_TIMES}))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_inovelli_dimmer:generate_test_message("button1", capabilities.button.button.pushed_5x({
        state_change = true }))
    }
  }
)

test.register_message_test(
  "Central Scene notification Button held should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_inovelli_dimmer.id, zw_test_utils.zwave_test_build_receive_command(CentralScene:Notification({
        scene_number = BUTTON_CONFIGURE_SCENE_3,
        key_attributes=CentralScene.key_attributes.KEY_PRESSED_1_TIME}))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_inovelli_dimmer:generate_test_message("button3", capabilities.button.button.pushed({
        state_change = true }))
    }
  }
)

test.run_registered_tests()
