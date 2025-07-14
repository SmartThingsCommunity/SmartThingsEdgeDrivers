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
  zigbee_test_utils.init_noop_health_check_timer()
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
        message = { mock_simple_device.id, tuya_utils.build_send_tuya_command(mock_simple_device, '\x01', tuya_utils.DP_TYPE_ENUM, '\x00', 2) }
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
        message = { mock_simple_device.id, tuya_utils.build_send_tuya_command(mock_simple_device, '\x01', tuya_utils.DP_TYPE_ENUM, '\x02', 3) }
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
        message = { mock_simple_device.id, tuya_utils.build_send_tuya_command(mock_simple_device, '\x01', tuya_utils.DP_TYPE_ENUM, '\x01', 4) }
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
        message = { mock_simple_device.id, tuya_utils.build_send_tuya_command(mock_simple_device, '\x02', tuya_utils.DP_TYPE_VALUE, '\x00\x00\x00\x3c', 5) }
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
        message = { mock_simple_device.id, tuya_utils.build_send_tuya_command(mock_simple_device, '\x02', tuya_utils.DP_TYPE_VALUE, '\x00\x00\x00\x32', 6) }
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
test.run_registered_tests()
