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

local test = require "integration_test"
local clusters = require "st.zigbee.zcl.clusters"
local OnOffCluster = clusters.OnOff
local SimpleMeteringCluster = clusters.SimpleMetering
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"

local mock_device = test.mock_device.build_test_zigbee_device({
  profile = t_utils.get_profile_definition("switch-power-energy.yml"),
  zigbee_endpoints = {
    [1] = {
      id = 1,
      manufacturer = "Jasco Products",
      model = "43078",
      server_clusters = { 0x0000, 0x0003, 0x0004, 0x0005, 0x0006, 0x0702, 0x0B05 },
      client_clusters = { 0x000A, 0x0019 }
    }
  }
})

local function test_init()
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

test.register_message_test(
  "Capability command On should be handled",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { mock_device.id, { capability = "switch", component = "main", command = "on", args = { } } }
    },
    {
      channel = "devices",
      direction = "send",
      message = {
        "register_native_capability_cmd_handler",
        { device_uuid = mock_device.id, capability_id = "switch", capability_cmd_id = "on" }
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, OnOffCluster.server.commands.On(mock_device) }
    }
  }
)

test.register_message_test(
  "Capability command Off should be handled",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { mock_device.id, { capability = "switch", component = "main", command = "off", args = { } } }
    },
    {
      channel = "devices",
      direction = "send",
      message = {
        "register_native_capability_cmd_handler",
        { device_uuid = mock_device.id, capability_id = "switch", capability_cmd_id = "off" }
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, OnOffCluster.server.commands.Off(mock_device) }
    }
  }
)

test.register_message_test(
  "Handle Power meter",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, SimpleMeteringCluster.attributes.InstantaneousDemand:build_test_attr_report(mock_device, 0x14D) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.powerMeter.power({ value = 33.3, unit = "W" }))
    }
  }
)

test.register_message_test(
  "Handle Energy meter",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = {mock_device.id, "added"}
    },
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, SimpleMeteringCluster.attributes.CurrentSummationDelivered:build_test_attr_report(mock_device, 0x15B3) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 0.5555, unit = "kWh" }))
    }
  }
)

test.run_registered_tests()
