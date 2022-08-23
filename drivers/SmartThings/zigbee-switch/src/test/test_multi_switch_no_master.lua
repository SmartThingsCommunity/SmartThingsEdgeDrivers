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
local capabilities = require "st.capabilities"
local OnOff = clusters.OnOff
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("multi-switch-no-master-2.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "DAWON_DNS",
        model = "PM-S240-ZB",
        server_clusters = {}
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
  test.mock_device.add_test_device(mock_device)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

test.register_message_test(
  "Reported on off status should be handled: on ep 1",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "init" }
    },
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_device,
                                                                                              true):from_endpoint(0x01) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",  capabilities.switch.switch.on())
    }
  }
)

test.register_message_test(
  "Reported on off status should be handled: on ep 2",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "init" }
    },
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_device,
                                                                                              true):from_endpoint(0x02) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("switch1",  capabilities.switch.switch.on())
    }
  }
)

test.register_message_test(
  "Reported on off status should be handled: off ep 1",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "init" }
    },
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_device,
                                                                                              false):from_endpoint(0x01) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",  capabilities.switch.switch.off())
    }
  }
)

test.register_message_test(
  "Reported on off status should be handled: off ep 2",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "init" }
    },
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_device,
                                                                                              false):from_endpoint(0x02) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("switch1",  capabilities.switch.switch.off())
    }
  }
)

test.register_message_test(
  "Capability on command switch on should be handled : main",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { mock_device.id, { capability = "switch", component = "main", command = "on", args = { } } }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, OnOff.server.commands.On(mock_device):to_endpoint(0x01) }
    }
  }
)

test.register_message_test(
  "Capability on command switch on should be handled : switch1",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { mock_device.id, { capability = "switch", component = "switch1", command = "on", args = { } } }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, OnOff.server.commands.On(mock_device):to_endpoint(0x02) }
    }
  }
)


test.register_message_test(
  "Capability off ommand switch on should be handled : main",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { mock_device.id, { capability = "switch", component = "main", command = "off", args = { } } }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, OnOff.server.commands.Off(mock_device):to_endpoint(0x01) }
    }
  }
)


test.register_message_test(
  "Capability off command switch on should be handled: switch1",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { mock_device.id, { capability = "switch", component = "switch1", command = "off", args = { } } }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, OnOff.server.commands.Off(mock_device):to_endpoint(0x02) }
    }
  }
)



test.run_registered_tests()
