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
--- @type st.zigbee.zcl.clusters.OccupancySensing
local OccupancySensing = clusters.OccupancySensing
local TemperatureMeasurement = clusters.TemperatureMeasurement
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"

local OccupancyAttribute = OccupancySensing.attributes.Occupancy

-- TODO: These tests fail, but it's because this device was not correctly supported in the driver
local mock_device = test.mock_device.build_test_zigbee_device(
    {
      profile = t_utils.get_profile_definition("motion.yml"),
      fingerprinted_endpoint_id = 0x01,
      zigbee_endpoints = {
        [1] = {
          id = 1,
          model = "E280-KR0A0Z0-HA",
          server_clusters = {0x0000, 0x0003, 0x0004, 0x0406}
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
  "Reported occupancy should be handled: active",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, OccupancyAttribute:build_test_attr_report(mock_device, 0x01) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.motionSensor.motion.active())
    }
  }
)

test.register_message_test(
    "Reported occupancy should be handled: active",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, OccupancyAttribute:build_test_attr_report(mock_device, 0x00) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.motionSensor.motion.inactive())
      }
    }
)


test.register_message_test(
  "Refresh should read all necessary attributes",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = {mock_device.id, "added"}
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
          mock_device.id,
          TemperatureMeasurement.attributes.MinMeasuredValue:read(mock_device)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
          mock_device.id,
          TemperatureMeasurement.attributes.MaxMeasuredValue:read(mock_device)
      }
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "refresh", component = "main", command = "refresh", args = {} }
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device.id,
        OccupancySensing.attributes.Occupancy:read(mock_device)
      }
    },
  }
)

test.register_coroutine_test(
  "Configure should configure all necessary attributes",
  function()
      test.wait_for_events()

      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
      test.socket.zigbee:__set_channel_ordering("relaxed")

      test.socket.zigbee:__expect_send(
              {
                  mock_device.id,
                  zigbee_test_utils.build_bind_request(mock_device,
                          zigbee_test_utils.mock_hub_eui,
                          OccupancySensing.ID)
              }
      )

      mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)


test.run_registered_tests()
