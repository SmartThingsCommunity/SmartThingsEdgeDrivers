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
      profile = t_utils.get_profile_definition("smoke-battery.yml"),
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "_TZE200_uebojraa",
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
  "added lifecycle event",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_simple_device.id, "added" })
    test.socket.capability:__expect_send(
      mock_simple_device:generate_test_message(
        "main",
        capabilities.smokeDetector.smoke.clear()
      )
    )
    test.socket.capability:__expect_send(
      mock_simple_device:generate_test_message(
        "main",
        capabilities.batteryLevel.battery.normal()
      )
    )
  end
)

test.register_message_test(
    "Battery level report should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_simple_device.id, tuya_utils.build_test_attr_report(mock_simple_device, '\x0e', tuya_utils.DP_TYPE_ENUM, '\x02', tuya_utils.TUYA_PRIVATE_CMD_REPORT) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_simple_device:generate_test_message("main", capabilities.batteryLevel.battery.normal())
      }
    }
)

test.register_message_test(
    "Battery level report should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_simple_device.id, tuya_utils.build_test_attr_report(mock_simple_device, '\x0e', tuya_utils.DP_TYPE_ENUM, '\x01', tuya_utils.TUYA_PRIVATE_CMD_REPORT) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_simple_device:generate_test_message("main", capabilities.batteryLevel.battery.warning())
      }
    }
)

test.register_message_test(
    "Battery level report should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_simple_device.id, tuya_utils.build_test_attr_report(mock_simple_device, '\x0e', tuya_utils.DP_TYPE_ENUM, '\x00', tuya_utils.TUYA_PRIVATE_CMD_REPORT) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_simple_device:generate_test_message("main", capabilities.batteryLevel.battery.critical())
      }
    }
)

test.register_message_test(
    "Reported smoke should be handled: detected",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_simple_device.id, tuya_utils.build_test_attr_report(mock_simple_device, '\x01', tuya_utils.DP_TYPE_ENUM, '\x00', tuya_utils.TUYA_PRIVATE_CMD_REPORT) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_simple_device:generate_test_message("main", capabilities.smokeDetector.smoke.detected())
      }
    }
)


test.register_message_test(
    "Reported smoke should be handled: detected(meian)",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_simple_device.id, tuya_utils.build_test_attr_report(mock_simple_device, '\x01', tuya_utils.DP_TYPE_ENUM, '\x01', tuya_utils.TUYA_PRIVATE_CMD_RESPONSE) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_simple_device:generate_test_message("main", capabilities.smokeDetector.smoke.detected())
      }
    }
)

test.register_message_test(
    "Reported smoke should be handled: clear",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_simple_device.id, tuya_utils.build_test_attr_report(mock_simple_device, '\x01', tuya_utils.DP_TYPE_ENUM, '\x01', tuya_utils.TUYA_PRIVATE_CMD_REPORT) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_simple_device:generate_test_message("main", capabilities.smokeDetector.smoke.clear())
      }
    }
)

test.register_message_test(
    "Reported smoke should be handled: clear(meian)",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_simple_device.id, tuya_utils.build_test_attr_report(mock_simple_device, '\x01', tuya_utils.DP_TYPE_ENUM, '\x00', tuya_utils.TUYA_PRIVATE_CMD_RESPONSE) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_simple_device:generate_test_message("main", capabilities.smokeDetector.smoke.clear())
      }
    }
)

test.run_registered_tests()