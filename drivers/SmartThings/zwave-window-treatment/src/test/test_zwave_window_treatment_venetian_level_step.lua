-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-- Tests for statelessWindowShadeLevelStep on the venetianBlind component of a
-- venetian window treatment (endpoint 2)

local capabilities = require "st.capabilities"
local constants = require "st.zwave.constants"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local t_utils = require "integration_test.utils"
local test = require "integration_test"
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({ version=4 })

local mock_device = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("fibaro-roller-shutter-venetian.yml"),
  zwave_endpoints = {
    {
      command_classes = {
        {value = zw.SWITCH_MULTILEVEL}
      }
    }
  },
  zwave_manufacturer_id = 0x010F,
  zwave_product_type = 0x1D01,
  zwave_product_id = 0x1000,
})

local function test_init()
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

local function report_level(endpoint, level)
  return {
    mock_device.id,
    zw_test_utils.zwave_test_build_receive_command(
      SwitchMultilevel:Report({
        target_value = level,
        current_value = level,
        duration = 0
      }, { encap = zw.ENCAP.AUTO, src_channel = endpoint, dst_channels = { 0 } })
    )
  }
end

local function queue_step(component, step)
  test.socket.capability:__queue_receive({
    mock_device.id,
    { capability = "statelessWindowShadeLevelStep", component = component, command = "stepShadeLevel", args = { step } }
  })
end

-- Expects the Set for a level sent to the venetian slats on endpoint 2
local function expect_venetian_set(level)
  test.socket.zwave:__expect_send(
    zw_test_utils.zwave_test_build_send_command(
      mock_device,
      SwitchMultilevel:Set({
        value = level,
        duration = constants.DEFAULT_DIMMING_DURATION
      }, { dst_channels = { 2 } })
    )
  )
end

test.register_coroutine_test(
  "stepShadeLevel on venetianBlind should step from the venetianBlind level and send to endpoint 2",
  function()
    test.socket.zwave:__queue_receive(report_level(2, 50))
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("venetianBlind", capabilities.windowShadeLevel.shadeLevel(50))
    )
    test.wait_for_events()

    queue_step("venetianBlind", 10)
    expect_venetian_set(60)
    test.wait_for_events()
  end,
  { min_api_version = 17 }
)

test.register_coroutine_test(
  "stepShadeLevel on venetianBlind should not use the main component level",
  function()
    test.socket.zwave:__queue_receive(report_level(1, 20))
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.partially_open())
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(20))
    )
    test.wait_for_events()

    test.socket.zwave:__queue_receive(report_level(2, 50))
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("venetianBlind", capabilities.windowShadeLevel.shadeLevel(50))
    )
    test.wait_for_events()

    queue_step("venetianBlind", 10)
    -- Built from the venetianBlind level (50), not main (20)
    expect_venetian_set(60)
    test.wait_for_events()
  end,
  { min_api_version = 17 }
)

test.run_registered_tests()
