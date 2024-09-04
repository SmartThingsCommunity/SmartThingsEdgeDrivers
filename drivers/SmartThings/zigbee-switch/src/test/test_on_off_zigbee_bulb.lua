-- Copyright 2022 SmartThings
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
local clusters = require "st.zigbee.zcl.clusters"
local OnOff = clusters.OnOff
local Level = clusters.Level
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"

local mock_simple_device = test.mock_device.build_test_zigbee_device(
    { profile = t_utils.get_profile_definition("on-off-level-intensity.yml") }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_simple_device)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

test.register_message_test(
    "Reported level should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = {
          mock_simple_device.id,
          Level.attributes.CurrentLevel:build_test_attr_report(mock_simple_device,
                                                                             math.floor(83 / 100 * 254))
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_simple_device:generate_test_message("main", capabilities.switchLevel.level(83))
      }
    }
)

test.register_message_test(
    "Reported on off status should be handled: on",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_simple_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_simple_device,
                                                                                                true) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_simple_device:generate_test_message("main", capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
    "Reported on off status should be handled: off",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_simple_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_simple_device,
                                                                                                false) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_simple_device:generate_test_message("main", capabilities.switch.switch.off())
      }
    }
)

test.register_message_test(
    "Capability command setLevel should be handled",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_simple_device.id, { capability = "switchLevel", component = "main", command = "setLevel", args = { 57, 0 } } }
      },
      {
        channel = "devices",
        direction = "send",
        message = {
          "register_native_capability_cmd_handler",
          { device_uuid = mock_simple_device.id, capability_id = "switchLevel", capability_cmd_id = "setLevel" }
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_simple_device.id, Level.server.commands.MoveToLevelWithOnOff(mock_simple_device,
                                                                                                    math.floor(57 * 0xFE / 100),
                                                                                                    0) }
      }
    }
)

test.register_coroutine_test(
    "doConfigure lifecycle should configure device",
    function()
      test.socket.device_lifecycle:__queue_receive({mock_simple_device.id, "doConfigure"})
      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.zigbee:__expect_send({
                                         mock_simple_device.id,
                                         OnOff.attributes.OnOff:read(mock_simple_device)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_simple_device.id,
                                         Level.attributes.CurrentLevel:read(mock_simple_device)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_simple_device.id,
                                         zigbee_test_utils.build_bind_request(mock_simple_device,
                                                                              zigbee_test_utils.mock_hub_eui,
                                                                              OnOff.ID)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_simple_device.id,
                                         OnOff.attributes.OnOff:configure_reporting(mock_simple_device, 0, 300)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_simple_device.id,
                                         zigbee_test_utils.build_bind_request(mock_simple_device,
                                                                              zigbee_test_utils.mock_hub_eui,
                                                                              Level.ID)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_simple_device.id,
                                         Level.attributes.CurrentLevel:configure_reporting(mock_simple_device,
                                                                                           1,
                                                                                           3600,
                                                                                           1)
                                       })
      mock_simple_device:expect_metadata_update({provisioning_state = "PROVISIONED"})
    end
)

test.register_coroutine_test(
    "health check coroutine",
    function()
      test.wait_for_events()

      test.mock_time.advance_time(10000)
      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.zigbee:__expect_send({ mock_simple_device.id, OnOff.attributes.OnOff:read(mock_simple_device) })
      test.socket.zigbee:__expect_send({ mock_simple_device.id, Level.attributes.CurrentLevel:read(mock_simple_device) })
      test.wait_for_events()
    end,
    {
      test_init = function()
        test.mock_device.add_test_device(mock_simple_device)
        test.timer.__create_and_queue_test_time_advance_timer(30, "interval", "health_check")
      end
    }
)

test.run_registered_tests()
