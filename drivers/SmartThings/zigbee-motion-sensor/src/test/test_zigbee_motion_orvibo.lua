-- Copyright 2021 SmartThings
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
local IASZone = clusters.IASZone
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"

local ZoneStatusAttribute = IASZone.attributes.ZoneStatus

local mock_device = test.mock_device.build_test_zigbee_device(
    {
      profile = t_utils.get_profile_definition("motion-battery.yml"),
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "ORVIBO",
          model = "895a2d80097f4ae2b2d40500d5e03dcc",
          server_clusters = {}
        }
      }
    }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
  zigbee_test_utils.init_noop_health_check_timer()
end
test.set_test_init_function(test_init)

test.register_message_test(
    "Reported motion should be handled: active",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, ZoneStatusAttribute:build_test_attr_report(mock_device, 0x0001) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.motionSensor.motion.active())
      }
    }
)

test.register_message_test(
    "Reported motion should be handled: inactive",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, ZoneStatusAttribute:build_test_attr_report(mock_device, 0x0000) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.motionSensor.motion.inactive())
      }
    }
)

test.register_message_test(
    "ZoneStatusChangeNotification should be handled: active",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, IASZone.client.commands.ZoneStatusChangeNotification.build_test_rx(mock_device, 0x0001, 0x00) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.motionSensor.motion.active())
      }
    }
)

test.register_message_test(
    "ZoneStatusChangeNotification should be handled: inactive",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, IASZone.client.commands.ZoneStatusChangeNotification.build_test_rx(mock_device, 0x0000, 0x00) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.motionSensor.motion.inactive())
      }
    }
)

test.register_coroutine_test(
    "State transnsition from opening to partially open",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.wait_for_events()
      test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          IASZone.client.commands.ZoneStatusChangeNotification.build_test_rx(mock_device, 0x0001, 0x00)
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.motionSensor.motion.active())
      )

      test.mock_time.advance_time(20)

      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.motionSensor.motion.inactive())
      )
      test.wait_for_events()
    end
)

test.register_coroutine_test(
    "State transnsition from opening to partially open",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.wait_for_events()
      test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          ZoneStatusAttribute:build_test_attr_report(mock_device, 0x0001)
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.motionSensor.motion.active())
      )

      test.mock_time.advance_time(20)

      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.motionSensor.motion.inactive())
      )
      test.wait_for_events()
    end
)


test.run_registered_tests()
