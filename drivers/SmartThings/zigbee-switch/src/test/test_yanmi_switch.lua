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
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local test = require "integration_test"
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local OnOff = clusters.OnOff

local common_switch_profile_def = t_utils.get_profile_definition("basic-switch.yml")


local mock_parent_device = test.mock_device.build_test_zigbee_device(
  {
    profile = common_switch_profile_def,
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "JNL",
        model = "Y-K003-001",
        server_clusters = { 0003,0004,0005,0006 }
      }
    },
    fingerprinted_endpoint_id = 0x01
  }
)

-- Switch 2 (Common Switch)
local mock_first_child = test.mock_device.build_test_child_device(
  {
    profile = common_switch_profile_def,
    device_network_id = string.format("%04X:%02X", mock_parent_device:get_short_address(), 2),
    parent_device_id = mock_parent_device.id,
    parent_assigned_child_key = string.format("%02X", 2)
  }
)

-- Switch 3 (Common Switch)
local mock_second_child = test.mock_device.build_test_child_device(
  {
    profile = common_switch_profile_def,
    device_network_id = string.format("%04X:%02X", mock_parent_device:get_short_address(), 3),
    parent_device_id = mock_parent_device.id,
    parent_assigned_child_key = string.format("%02X", 3)
  }
)



zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
  test.mock_device.add_test_device(mock_parent_device)
  test.mock_device.add_test_device(mock_first_child)
  test.mock_device.add_test_device(mock_second_child)
end

test.set_test_init_function(test_init)

-- 4 Common Switch Tests
test.register_message_test(
    "Reported on off status should be handled by parent device: on",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent_device.id, "init" }
      },
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_parent_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_parent_device,
            true)                               :from_endpoint(0x01) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent_device:generate_test_message("main", capabilities.switch.switch.on())
      },
      {
        channel = "devices",
        direction = "send",
        message = {
          "register_native_capability_attr_handler",
          { device_uuid = mock_parent_device.id, capability_id = "switch", capability_attr_id = "switch" }
        }
      },
    }
)

test.register_message_test(
    "Reported on off status should be handled by first child device: on",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent_device.id, "init" }
      },
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_first_child.id, OnOff.attributes.OnOff:build_test_attr_report(mock_parent_device,
            true)                             :from_endpoint(0x02) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_first_child:generate_test_message("main", capabilities.switch.switch.on())
      },
      {
        channel = "devices",
        direction = "send",
        message = {
          "register_native_capability_attr_handler",
          { device_uuid = mock_first_child.id, capability_id = "switch", capability_attr_id = "switch" }
        }
      },
    }
)

test.register_message_test(
    "Reported on off status should be handled by Second child device: on",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent_device.id, "init" }
      },
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_second_child.id, OnOff.attributes.OnOff:build_test_attr_report(mock_parent_device,
            true)                              :from_endpoint(0x03) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_second_child:generate_test_message("main", capabilities.switch.switch.on())
      },
      {
        channel = "devices",
        direction = "send",
        message = {
          "register_native_capability_attr_handler",
          { device_uuid = mock_second_child.id, capability_id = "switch", capability_attr_id = "switch" }
        }
      },
    }
)


test.register_message_test(
    "reported on off status should be handled by parent device: off",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent_device.id, "init" }
      },
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_parent_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_parent_device,
            false)                               :from_endpoint(0x01) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent_device:generate_test_message("main", capabilities.switch.switch.off())
      },
      {
        channel = "devices",
        direction = "send",
        message = {
          "register_native_capability_attr_handler",
          { device_uuid = mock_parent_device.id, capability_id = "switch", capability_attr_id = "switch" }
        }
      },
    }
)

test.register_message_test(
    "Reported on off status should be handled by first child device: off",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent_device.id, "init" }
      },
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_first_child.id, OnOff.attributes.OnOff:build_test_attr_report(mock_parent_device,
        false)                             :from_endpoint(0x02) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_first_child:generate_test_message("main", capabilities.switch.switch.off())
      },
      {
        channel = "devices",
        direction = "send",
        message = {
          "register_native_capability_attr_handler",
          { device_uuid = mock_first_child.id, capability_id = "switch", capability_attr_id = "switch" }
        }
      },
    }
)

test.register_message_test(
    "Reported on off status should be handled by Second child device: off",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent_device.id, "init" }
      },
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_second_child.id, OnOff.attributes.OnOff:build_test_attr_report(mock_parent_device,
        false)                              :from_endpoint(0x03) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_second_child:generate_test_message("main", capabilities.switch.switch.off())
      },
      {
        channel = "devices",
        direction = "send",
        message = {
          "register_native_capability_attr_handler",
          { device_uuid = mock_second_child.id, capability_id = "switch", capability_attr_id = "switch" }
        }
      },
    }
)


test.register_message_test(
    "Capability on command switch on should be handled : parent device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent_device.id, "init" }
      },
      {
        channel = "capability",
        direction = "receive",
        message = { mock_parent_device.id, { capability = "switch", component = "main", command = "on", args = { } } }
      },
      {
        channel = "devices",
        direction = "send",
        message = {
          "register_native_capability_cmd_handler",
          { device_uuid = mock_parent_device.id, capability_id = "switch", capability_cmd_id = "on" }
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_parent_device.id, OnOff.server.commands.On(mock_parent_device):to_endpoint(0x01) }
      }
    }
)

test.register_message_test(
    "Capability on command switch on should be handled : first child device",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_first_child.id, { capability = "switch", component = "main", command = "on", args = { } } }
      },
      {
        channel = "devices",
        direction = "send",
        message = {
          "register_native_capability_cmd_handler",
          { device_uuid = mock_first_child.id, capability_id = "switch", capability_cmd_id = "on" }
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_parent_device.id, OnOff.server.commands.On(mock_parent_device):to_endpoint(0x02) }
      }
    }
)

test.register_message_test(
    "Capability on command switch on should be handled : second child device",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_second_child.id, { capability = "switch", component = "main", command = "on", args = { } } }
      },
      {
        channel = "devices",
        direction = "send",
        message = {
          "register_native_capability_cmd_handler",
          { device_uuid = mock_second_child.id, capability_id = "switch", capability_cmd_id = "on" }
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_parent_device.id, OnOff.server.commands.On(mock_parent_device):to_endpoint(0x03) }
      }
    }
)




test.register_message_test(
    "Capability off command switch off should be handled : parent device",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_parent_device.id, { capability = "switch", component = "main", command = "off", args = { } } }
      },
      {
        channel = "devices",
        direction = "send",
        message = {
          "register_native_capability_cmd_handler",
          { device_uuid = mock_parent_device.id, capability_id = "switch", capability_cmd_id = "off" }
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_parent_device.id, OnOff.server.commands.Off(mock_parent_device):to_endpoint(0x01) }
      }
    }
)

test.register_message_test(
    "Capability off command switch off should be handled : first child device",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_first_child.id, { capability = "switch", component = "main", command = "off", args = { } } }
      },
      {
        channel = "devices",
        direction = "send",
        message = {
          "register_native_capability_cmd_handler",
          { device_uuid = mock_first_child.id, capability_id = "switch", capability_cmd_id = "off" }
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_parent_device.id, OnOff.server.commands.Off(mock_parent_device):to_endpoint(0x02) }
      }
    }
)

test.register_message_test(
    "Capability off command switch off should be handled : second child device",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_second_child.id, { capability = "switch", component = "main", command = "off", args = { } } }
      },
      {
        channel = "devices",
        direction = "send",
        message = {
          "register_native_capability_cmd_handler",
          { device_uuid = mock_second_child.id, capability_id = "switch", capability_cmd_id = "off" }
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_parent_device.id, OnOff.server.commands.Off(mock_parent_device):to_endpoint(0x03) }
      }
    }
)

test.run_registered_tests()
