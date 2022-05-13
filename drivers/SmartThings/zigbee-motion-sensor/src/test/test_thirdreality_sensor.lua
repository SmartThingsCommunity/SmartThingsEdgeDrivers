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
local PowerConfiguration = clusters.PowerConfiguration
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"

local mock_device1 = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("motion-battery.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "Third Reality, Inc",
        model = "3RMS16BZ",
        server_clusters = {0x0000, 0x0001, 0x0500}
      }
    }
  }
)

local mock_device2 = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("motion-battery.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "THIRDREALITY",
        model = "3RMS16BZ",
        server_clusters = {0x0000, 0x0001, 0x0500}
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device1)
  test.mock_device.add_test_device(mock_device2)
  zigbee_test_utils.init_noop_health_check_timer()
end
test.set_test_init_function(test_init)

test.register_message_test(
  "Battery percentage (55) report should be handled -> 55%",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device1.id, PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device1, 55) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device1:generate_test_message("main", capabilities.battery.battery(55))
    }
  }
)

test.register_message_test(
  "Battery percentage (120) report should be handled -> 100%",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device1.id, PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device1, 120) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device1:generate_test_message("main", capabilities.battery.battery(100))
    }
  }
)

test.register_message_test(
  "Battery percentage report (55) should be handled -> 55%",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device2.id, PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device2, 55) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device2:generate_test_message("main", capabilities.battery.battery(55))
    }
  }
)

test.register_message_test(
  "Battery percentage (120) report should be handled -> 100%",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device2.id, PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device1, 120) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device2:generate_test_message("main", capabilities.battery.battery(100))
    }
  }
)

test.run_registered_tests()
