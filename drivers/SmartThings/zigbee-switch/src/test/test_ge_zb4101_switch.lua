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

local test = require "integration_test"
local t_utils = require "integration_test.utils"
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local constants = require "st.zigbee.constants"

local SimpleMetering = clusters.SimpleMetering

local mock_device = test.mock_device.build_test_zigbee_device(
  { profile = t_utils.get_profile_definition("switch-power-smartplug.yml"),
    fingerprinted_endpoint_id = 0x01,
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "Jasco Products",
        model = "45853",
        server_clusters = {SimpleMetering.ID}
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
  mock_device:set_field("_configuration_version", 1, {persist = true})
  mock_device:set_field(constants.SIMPLE_METERING_DIVISOR_KEY, 10000, { persist = true })
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

test.register_message_test(
  "Handle Power meter",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, SimpleMetering.attributes.InstantaneousDemand:build_test_attr_report(mock_device, 931) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.powerMeter.power({ value = 93.1, unit = "W" }))
    }
  }
)

test.run_registered_tests()
