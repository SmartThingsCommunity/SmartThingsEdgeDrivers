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
local IASZone = clusters.IASZone
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local base64 = require "st.base64"
local t_utils = require "integration_test.utils"

local ZoneStatusAttribute = IASZone.attributes.ZoneStatus

local mock_device = test.mock_device.build_test_zigbee_device(
    {
      profile = t_utils.get_profile_definition("motion-contact-presence.yml"),
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "GatorSystem",
          model = "GSHW01",
          server_clusters = {0x0500, 0x0000}
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

test.register_coroutine_test(
    "Motion active handler after 120 seconds inactive",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(120, "oneshot")
      test.socket.zigbee:__queue_receive(
          {
            mock_device.id,
            ZoneStatusAttribute:build_test_attr_report(mock_device, 0x0001),
          }
      )
      test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.motionSensor.motion.active()))
      test.mock_time.advance_time(120)
      test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.motionSensor.motion.inactive()))
    end
)

test.register_coroutine_test(
    "Presence detection handler after 60 seconds not_present",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(60, "oneshot")
      test.socket.zigbee:__queue_receive(
          {
            mock_device.id,
            ZoneStatusAttribute:build_test_attr_report(mock_device, 0x8000),
          }
      )
      test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.presenceSensor.presence.present()))
      test.mock_time.advance_time(60)
      test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.presenceSensor.presence.not_present()))
    end
)

test.register_coroutine_test(
    "Contact open handler",
    function()
      test.socket.zigbee:__queue_receive(
          {
            mock_device.id,
            ZoneStatusAttribute:build_test_attr_report(mock_device, 0x4000),
          }
      )
      test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.contactSensor.contact.open()))
    end
)

test.register_coroutine_test(
    "Contact close handler",
    function()
      test.socket.zigbee:__queue_receive(
          {
            mock_device.id,
            ZoneStatusAttribute:build_test_attr_report(mock_device, 0x2000),
          }
      )
      test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.contactSensor.contact.closed()))
    end
)

test.register_coroutine_test(
    "Full Battery handler",
    function()
      test.socket.zigbee:__queue_receive(
          {
            mock_device.id,
            ZoneStatusAttribute:build_test_attr_report(mock_device, 0x1000),
          }
      )
      test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.battery.battery(100)))
    end
)

test.register_coroutine_test(
    "Battery out handler",
    function()
      test.socket.zigbee:__queue_receive(
          {
            mock_device.id,
            ZoneStatusAttribute:build_test_attr_report(mock_device, 0x0800),
          }
      )
      test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.battery.battery(0)))
    end
)

test.register_coroutine_test(
    "Battery out handler",
    function()
      test.socket.zigbee:__queue_receive(
          {
            mock_device.id,
            ZoneStatusAttribute:build_test_attr_report(mock_device, 0x0008),
          }
      )
      test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.battery.battery(10)))
    end
)

test.register_coroutine_test(
    "Handle Configure lifecycle",
    function()
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added"})
      test.socket.capability:__set_channel_ordering("relaxed")
      -- test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.battery.battery(100)))
      -- test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.contactSensor.contact.closed()))
      -- test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.presenceSensor.presence.not_present()))
      -- test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.motionSensor.motion.inactive()))
      mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
      test.wait_for_events()
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
  end
)

test.run_registered_tests()
