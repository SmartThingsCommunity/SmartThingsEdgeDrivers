-- Copyright 2025 SmartThings
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

-- Mock out globals
local test = require "integration_test"
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"
local clusters = require "st.zigbee.zcl.clusters"
local tuya_utils = require "tuya_utils"

local Basic = clusters.Basic

local mock_simple_device = test.mock_device.build_test_zigbee_device(
    {
      profile = t_utils.get_profile_definition("window-treatment-reverse.yml"),
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "_TZE284_nladmfvf",
          model = "TS0601",
          server_clusters = { 0xef00 }
        }
      }
    }
)

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
  test.mock_device.add_test_device(mock_simple_device)
  test.socket.capability:__expect_send(
    mock_simple_device:generate_test_message("main", capabilities.windowShadePreset.supportedCommands({"presetPosition", "setPresetPosition"}, {visibility = {displayed=false}}))
  )
  test.socket.capability:__expect_send(
    mock_simple_device:generate_test_message("main", capabilities.windowShadePreset.position(50, {visibility = {displayed=false}}))
  )
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "doConfigure lifecycle event",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_simple_device.id, "doConfigure" })
    test.socket.zigbee:__expect_send({ mock_simple_device.id, tuya_utils.build_tuya_magic_spell_message(mock_simple_device) })
    test.socket.zigbee:__expect_send({ mock_simple_device.id, zigbee_test_utils.build_bind_request(mock_simple_device, zigbee_test_utils.mock_hub_eui, Basic.ID) })
    test.socket.zigbee:__expect_send({ mock_simple_device.id, Basic.attributes.ApplicationVersion:configure_reporting(mock_simple_device, 30, 300, 1) })
    mock_simple_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_coroutine_test(
  "Handle reverseCurtainDirection in infochanged",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    local updates = {
      preferences = {
      }
    }
    updates.preferences.reverse = true
    test.socket.device_lifecycle:__queue_receive(mock_simple_device:generate_info_changed(updates))
    test.socket.zigbee:__expect_send(
      {
        mock_simple_device.id,
        tuya_utils.build_send_tuya_command(mock_simple_device, '\x05', tuya_utils.DP_TYPE_ENUM, '\x01', 0)
      }
    )
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.wait_for_events()
    test.mock_time.advance_time(2)
    updates.preferences.reverse = false
    test.socket.device_lifecycle:__queue_receive(mock_simple_device:generate_info_changed(updates))
    test.socket.zigbee:__expect_send(
      {
        mock_simple_device.id,
        tuya_utils.build_send_tuya_command(mock_simple_device, '\x05', tuya_utils.DP_TYPE_ENUM, '\x00', 1)
      }
    )
  end
)

test.register_coroutine_test(
  "added lifecycle event",
  function()
    -- The initial window shade event should be send during the device's first time onboarding
    test.socket.device_lifecycle:__queue_receive({ mock_simple_device.id, "added" })
    test.socket.capability:__expect_send(
      mock_simple_device:generate_test_message(
        "main",
        capabilities.windowShade.supportedWindowShadeCommands({ "open", "close", "pause" }, {visibility = {displayed = false}})
      )
    )
    test.socket.capability:__expect_send(
      mock_simple_device:generate_test_message(
        "main",
        capabilities.windowShadeLevel.shadeLevel(0)
      )
    )
    test.socket.capability:__expect_send(
      mock_simple_device:generate_test_message(
        "main",
        capabilities.windowShade.windowShade.closed()
      )
    )
    test.socket.capability:__expect_send(
      mock_simple_device:generate_test_message("main", capabilities.windowShadePreset.supportedCommands({"presetPosition", "setPresetPosition"}, {visibility = {displayed=false}}))
    )
    test.wait_for_events()
    -- Avoid sending the initial window shade event after driver switch-over, as the switch-over event itself re-triggers the added lifecycle.
    test.socket.device_lifecycle:__queue_receive({ mock_simple_device.id, "added" })
    test.socket.capability:__expect_send(
      mock_simple_device:generate_test_message(
        "main",
        capabilities.windowShade.supportedWindowShadeCommands({ "open", "close", "pause" }, {visibility = {displayed = false}})
      )
    )

    test.socket.capability:__expect_send(
      mock_simple_device:generate_test_message("main", capabilities.windowShadePreset.supportedCommands({"presetPosition", "setPresetPosition"}, {visibility = {displayed=false}}))
    )
  end
)

test.register_message_test(
    "Handle Window shade open command",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_simple_device.id, { capability = "windowShade", component = "main", command = "open", args = {}} }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_simple_device.id, tuya_utils.build_send_tuya_command(mock_simple_device, '\x01', tuya_utils.DP_TYPE_ENUM, '\x00', 0) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_simple_device:generate_test_message("main",  capabilities.windowShade.windowShade.opening())
      }
    }
)

test.register_message_test(
    "Handle Window shade close command",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_simple_device.id, { capability = "windowShade", component = "main", command = "close", args = {}} }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_simple_device.id, tuya_utils.build_send_tuya_command(mock_simple_device, '\x01', tuya_utils.DP_TYPE_ENUM, '\x02', 0) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_simple_device:generate_test_message("main",  capabilities.windowShade.windowShade.closing())
      }
    }
)

test.register_message_test(
    "Handle Window shade pause command",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_simple_device.id, { capability = "windowShade", component = "main", command = "pause", args = {} } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_simple_device.id, tuya_utils.build_send_tuya_command(mock_simple_device, '\x01', tuya_utils.DP_TYPE_ENUM, '\x01', 0) }
      }
    }
)

test.register_message_test(
    "Handle Window Shade level command",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_simple_device.id, { capability = "windowShadeLevel", component = "main", command = "setShadeLevel", args = { 40 }} }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_simple_device.id, tuya_utils.build_send_tuya_command(mock_simple_device, '\x02', tuya_utils.DP_TYPE_VALUE, '\x00\x00\x00\x3c', 0) }
      }
    }
)

test.register_message_test(
    "Handle Window Shade preset command",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_simple_device.id, { capability = "windowShadePreset", component = "main", command = "presetPosition", args = {}} }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_simple_device.id, tuya_utils.build_send_tuya_command(mock_simple_device, '\x02', tuya_utils.DP_TYPE_VALUE, '\x00\x00\x00\x32', 0) }
      }
    }
)

test.register_message_test(
    "Handle tuya cluster message report",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_simple_device.id, tuya_utils.build_test_attr_report(mock_simple_device, '\x03', tuya_utils.DP_TYPE_VALUE, '\x00\x00\x00\x28', 0x01) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_simple_device:generate_test_message("main",  capabilities.windowShadeLevel.shadeLevel(40))
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_simple_device:generate_test_message("main",  capabilities.windowShade.windowShade("partially open"))
      }
    }
)

test.register_message_test(
    "Handle Window Shade step level command - step up",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_simple_device.id, { capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { 10 }, stepSize = 10 } }
      },
      {
        channel = "zigbee",
        direction = "send",
        -- For _TZE284_nladmfvf, level is inverted: 100 - 10 = 90 (0x5A)
        message = { mock_simple_device.id, tuya_utils.build_send_tuya_command(mock_simple_device, '\x02', tuya_utils.DP_TYPE_VALUE, '\x00\x00\x00\x5a', 0) }
      }
    }
)

test.register_message_test(
    "Handle Window Shade step level command - step down",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_simple_device.id, { capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { -10 }, stepSize = -10 } }
      },
      {
        channel = "zigbee",
        direction = "send",
        -- For _TZE284_nladmfvf, level is inverted: 100 - 0 = 100 (0x64), but clamped to 0 so 100 - 0 = 100
        message = { mock_simple_device.id, tuya_utils.build_send_tuya_command(mock_simple_device, '\x02', tuya_utils.DP_TYPE_VALUE, '\x00\x00\x00\x64', 0) }
      }
    }
)

test.register_coroutine_test(
  "Handle Window Shade step level command - step up from current level",
  function()
    -- First, simulate a current shade level of 40
    test.socket.zigbee:__queue_receive({
      mock_simple_device.id,
      tuya_utils.build_test_attr_report(mock_simple_device, '\x03', tuya_utils.DP_TYPE_VALUE, '\x00\x00\x00\x28', 0x01)
    })
    test.socket.capability:__expect_send(
      mock_simple_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(40))
    )
    test.socket.capability:__expect_send(
      mock_simple_device:generate_test_message("main", capabilities.windowShade.windowShade("partially open"))
    )
    test.wait_for_events()

    -- Then send step command with stepSize 20, should result in level 60
    -- For _TZE284_nladmfvf, level is inverted: 100 - 60 = 40 (0x28)
    test.socket.capability:__queue_receive({
      mock_simple_device.id,
      { capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { 20 }, stepSize = 20 }
    })
    test.socket.zigbee:__expect_send({
      mock_simple_device.id,
      tuya_utils.build_send_tuya_command(mock_simple_device, '\x02', tuya_utils.DP_TYPE_VALUE, '\x00\x00\x00\x28', 0)
    })
  end
)

test.register_coroutine_test(
  "Handle Window Shade step level command - step up clamped to 100",
  function()
    -- First, simulate a current shade level of 90
    test.socket.zigbee:__queue_receive({
      mock_simple_device.id,
      tuya_utils.build_test_attr_report(mock_simple_device, '\x03', tuya_utils.DP_TYPE_VALUE, '\x00\x00\x00\x5a', 0x01)
    })
    test.socket.capability:__expect_send(
      mock_simple_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(90))
    )
    test.socket.capability:__expect_send(
      mock_simple_device:generate_test_message("main", capabilities.windowShade.windowShade("partially open"))
    )
    test.wait_for_events()

    -- Then send step command with stepSize 20, should be clamped to 100
    -- For _TZE284_nladmfvf, level is inverted: 100 - 100 = 0 (0x00)
    test.socket.capability:__queue_receive({
      mock_simple_device.id,
      { capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { 20 }, stepSize = 20 }
    })
    test.socket.zigbee:__expect_send({
      mock_simple_device.id,
      tuya_utils.build_send_tuya_command(mock_simple_device, '\x02', tuya_utils.DP_TYPE_VALUE, '\x00\x00\x00\x00', 0)
    })
  end
)

test.register_coroutine_test(
  "Handle Window Shade step level command - step down clamped to 0",
  function()
    -- First, simulate a current shade level of 10
    test.socket.zigbee:__queue_receive({
      mock_simple_device.id,
      tuya_utils.build_test_attr_report(mock_simple_device, '\x03', tuya_utils.DP_TYPE_VALUE, '\x00\x00\x00\x0a', 0x01)
    })
    test.socket.capability:__expect_send(
      mock_simple_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(10))
    )
    test.socket.capability:__expect_send(
      mock_simple_device:generate_test_message("main", capabilities.windowShade.windowShade("partially open"))
    )
    test.wait_for_events()

    -- Then send step command with stepSize -20, should be clamped to 0
    -- For _TZE284_nladmfvf, level is inverted: 100 - 0 = 100 (0x64)
    test.socket.capability:__queue_receive({
      mock_simple_device.id,
      { capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { -20 }, stepSize = -20 }
    })
    test.socket.zigbee:__expect_send({
      mock_simple_device.id,
      tuya_utils.build_send_tuya_command(mock_simple_device, '\x02', tuya_utils.DP_TYPE_VALUE, '\x00\x00\x00\x64', 0)
    })
  end
)

test.register_coroutine_test(
  "Handle Window Shade step level command - uses latest_target_level when available",
  function()
    -- First, simulate a current shade level of 40
    test.socket.zigbee:__queue_receive({
      mock_simple_device.id,
      tuya_utils.build_test_attr_report(mock_simple_device, '\x03', tuya_utils.DP_TYPE_VALUE, '\x00\x00\x00\x28', 0x01)
    })
    test.socket.capability:__expect_send(
      mock_simple_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(40))
    )
    test.socket.capability:__expect_send(
      mock_simple_device:generate_test_message("main", capabilities.windowShade.windowShade("partially open"))
    )
    test.wait_for_events()

    -- Send first step command to set latest_target_level to 50
    -- For _TZE284_nladmfvf, level is inverted: 100 - 50 = 50 (0x32)
    test.socket.capability:__queue_receive({
      mock_simple_device.id,
      { capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { 10 }, stepSize = 10 }
    })
    test.socket.zigbee:__expect_send({
      mock_simple_device.id,
      tuya_utils.build_send_tuya_command(mock_simple_device, '\x02', tuya_utils.DP_TYPE_VALUE, '\x00\x00\x00\x32', 0)
    })
    test.wait_for_events()

    -- Send second step command before timeout - should use latest_target_level (50) as base
    -- Target = 50 + 10 = 60, For _TZE284_nladmfvf: 100 - 60 = 40 (0x28)
    -- Packet ID is 1 because it was incremented after the first step command
    test.socket.capability:__queue_receive({
      mock_simple_device.id,
      { capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { 10 }, stepSize = 10 }
    })
    test.socket.zigbee:__expect_send({
      mock_simple_device.id,
      tuya_utils.build_send_tuya_command(mock_simple_device, '\x02', tuya_utils.DP_TYPE_VALUE, '\x00\x00\x00\x28', 1)
    })
  end
)

test.run_registered_tests()