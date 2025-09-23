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

local tuya_utils = require "tuya_utils"

local mock_base_device = test.mock_device.build_test_zigbee_device(
  {
    label = "Switch",
    profile = t_utils.get_profile_definition("basic-switch.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "_TZE204_h2rctifa",
        model = "TS0601",
        server_clusters = { 0xef00 }
      }
    },
    fingerprinted_endpoint_id = 0x01
  }
)

local mock_parent_device = test.mock_device.build_test_zigbee_device(
    {
      profile = t_utils.get_profile_definition("basic-switch.yml"),
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "_TZE204_h2rctifa",
          model = "TS0601",
          server_clusters = { 0xef00 }
        }
      },
      fingerprinted_endpoint_id = 0x01
    }
)

local first_mock_child_device = test.mock_device.build_test_child_device({
  profile = t_utils.get_profile_definition("basic-switch.yml"),
  device_network_id = string.format("%04X:%02X", mock_parent_device:get_short_address(), 2),
  parent_device_id = mock_parent_device.id,
  parent_assigned_child_key = string.format("%02X", 2)
})

local second_mock_child_device = test.mock_device.build_test_child_device({
  profile = t_utils.get_profile_definition("basic-switch.yml"),
  device_network_id = string.format("%04X:%02X", mock_parent_device:get_short_address(), 3),
  parent_device_id = mock_parent_device.id,
  parent_assigned_child_key = string.format("%02X", 3)
})

local third_mock_child_device = test.mock_device.build_test_child_device({
  profile = t_utils.get_profile_definition("basic-switch.yml"),
  device_network_id = string.format("%04X:%02X", mock_parent_device:get_short_address(), 4),
  parent_device_id = mock_parent_device.id,
  parent_assigned_child_key = string.format("%02X", 4)
})

local fourth_mock_child_device = test.mock_device.build_test_child_device({
  profile = t_utils.get_profile_definition("basic-switch.yml"),
  device_network_id = string.format("%04X:%02X", mock_parent_device:get_short_address(), 5),
  parent_device_id = mock_parent_device.id,
  parent_assigned_child_key = string.format("%02X", 5)
})

local fifth_mock_child_device = test.mock_device.build_test_child_device({
  profile = t_utils.get_profile_definition("basic-switch.yml"),
  device_network_id = string.format("%04X:%02X", mock_parent_device:get_short_address(), 6),
  parent_device_id = mock_parent_device.id,
  parent_assigned_child_key = string.format("%02X", 6)
})

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
  test.mock_device.add_test_device(mock_base_device)
  test.mock_device.add_test_device(mock_parent_device)
  test.mock_device.add_test_device(first_mock_child_device)
  test.mock_device.add_test_device(second_mock_child_device)
  test.mock_device.add_test_device(third_mock_child_device)
  test.mock_device.add_test_device(fourth_mock_child_device)
  test.mock_device.add_test_device(fifth_mock_child_device)end

test.set_test_init_function(test_init)

test.register_message_test(
    "Reported on off status should be handled: on dp 1",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent_device.id, "init" }
      },
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_parent_device.id, tuya_utils.build_test_attr_report(mock_parent_device, '\x01', tuya_utils.DP_TYPE_BOOL, '\x01', tuya_utils.TUYA_PRIVATE_CMD_REPORT) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent_device:generate_test_message("main",  capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
    "Reported on off status should be handled: on dp 2",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { first_mock_child_device.id, "init" }
      },
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_parent_device.id, tuya_utils.build_test_attr_report(mock_parent_device, '\x02', tuya_utils.DP_TYPE_BOOL, '\x01', tuya_utils.TUYA_PRIVATE_CMD_REPORT) }
      },
      {
        channel = "capability",
        direction = "send",
        message = first_mock_child_device:generate_test_message("main",  capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
    "Reported on off status should be handled: on dp 3",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { second_mock_child_device.id, "init" }
      },
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_parent_device.id, tuya_utils.build_test_attr_report(mock_parent_device, '\x03', tuya_utils.DP_TYPE_BOOL, '\x01', tuya_utils.TUYA_PRIVATE_CMD_REPORT) }
      },
      {
        channel = "capability",
        direction = "send",
        message = second_mock_child_device:generate_test_message("main",  capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
    "Reported on off status should be handled: on dp 4",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { third_mock_child_device.id, "init" }
      },
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_parent_device.id, tuya_utils.build_test_attr_report(mock_parent_device, '\x04', tuya_utils.DP_TYPE_BOOL, '\x01', tuya_utils.TUYA_PRIVATE_CMD_REPORT) }
      },
      {
        channel = "capability",
        direction = "send",
        message = third_mock_child_device:generate_test_message("main",  capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
    "Reported on off status should be handled: on dp 5",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { fourth_mock_child_device.id, "init" }
      },
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_parent_device.id, tuya_utils.build_test_attr_report(mock_parent_device, '\x05', tuya_utils.DP_TYPE_BOOL, '\x01', tuya_utils.TUYA_PRIVATE_CMD_REPORT) }
      },
      {
        channel = "capability",
        direction = "send",
        message = fourth_mock_child_device:generate_test_message("main",  capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
    "Reported on off status should be handled: on dp 6",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { fifth_mock_child_device.id, "init" }
      },
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_parent_device.id, tuya_utils.build_test_attr_report(mock_parent_device, '\x06', tuya_utils.DP_TYPE_BOOL, '\x01', tuya_utils.TUYA_PRIVATE_CMD_REPORT) }
      },
      {
        channel = "capability",
        direction = "send",
        message = fifth_mock_child_device:generate_test_message("main",  capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
  "Capability on command switch on should be handled : dp 1",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { mock_parent_device.id, { capability = "switch", component = "main", command = "on", args = { } } }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_parent_device.id, tuya_utils.build_send_tuya_command(mock_parent_device, '\x01', tuya_utils.DP_TYPE_BOOL, '\x01', 0) }
    }
  }
)

test.register_message_test(
  "Capability on command switch on should be handled : dp 2",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { first_mock_child_device.id, { capability = "switch", component = "main", command = "on", args = { } } }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_parent_device.id, tuya_utils.build_send_tuya_command(mock_parent_device, '\x02', tuya_utils.DP_TYPE_BOOL, '\x01', 1) }
    }
  }
)

test.register_message_test(
  "Capability on command switch on should be handled : dp 3",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { second_mock_child_device.id, { capability = "switch", component = "main", command = "on", args = { } } }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_parent_device.id, tuya_utils.build_send_tuya_command(mock_parent_device, '\x03', tuya_utils.DP_TYPE_BOOL, '\x01', 2) }
    }
  }
)

test.register_message_test(
  "Capability on command switch on should be handled : dp 4",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { third_mock_child_device.id, { capability = "switch", component = "main", command = "on", args = { } } }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_parent_device.id, tuya_utils.build_send_tuya_command(mock_parent_device, '\x04', tuya_utils.DP_TYPE_BOOL, '\x01', 3) }
    }
  }
)

test.register_message_test(
  "Capability on command switch on should be handled : dp 5",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { fourth_mock_child_device.id, { capability = "switch", component = "main", command = "on", args = { } } }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_parent_device.id, tuya_utils.build_send_tuya_command(mock_parent_device, '\x05', tuya_utils.DP_TYPE_BOOL, '\x01', 4) }
    }
  }
)

test.register_message_test(
  "Capability on command switch on should be handled : dp 6",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { fifth_mock_child_device.id, { capability = "switch", component = "main", command = "on", args = { } } }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_parent_device.id, tuya_utils.build_send_tuya_command(mock_parent_device, '\x06', tuya_utils.DP_TYPE_BOOL, '\x01', 5) }
    }
  }
)

test.register_message_test(
  "Capability off command switch off should be handled : dp 1",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { mock_parent_device.id, { capability = "switch", component = "main", command = "off", args = { } } }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_parent_device.id, tuya_utils.build_send_tuya_command(mock_parent_device, '\x01', tuya_utils.DP_TYPE_BOOL, '\x00', 6) }
    }
  }
)

test.register_message_test(
  "Capability off command switch off should be handled : dp 2",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { first_mock_child_device.id, { capability = "switch", component = "main", command = "off", args = { } } }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_parent_device.id, tuya_utils.build_send_tuya_command(mock_parent_device, '\x02', tuya_utils.DP_TYPE_BOOL, '\x00', 7) }
    }
  }
)

test.register_message_test(
  "Capability off command switch off should be handled : dp 3",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { second_mock_child_device.id, { capability = "switch", component = "main", command = "off", args = { } } }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_parent_device.id, tuya_utils.build_send_tuya_command(mock_parent_device, '\x03', tuya_utils.DP_TYPE_BOOL, '\x00', 8) }
    }
  }
)

test.register_message_test(
  "Capability off command switch off should be handled : dp 4",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { third_mock_child_device.id, { capability = "switch", component = "main", command = "off", args = { } } }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_parent_device.id, tuya_utils.build_send_tuya_command(mock_parent_device, '\x04', tuya_utils.DP_TYPE_BOOL, '\x00', 9) }
    }
  }
)

test.register_message_test(
  "Capability off command switch off should be handled : dp 5",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { fourth_mock_child_device.id, { capability = "switch", component = "main", command = "off", args = { } } }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_parent_device.id, tuya_utils.build_send_tuya_command(mock_parent_device, '\x05', tuya_utils.DP_TYPE_BOOL, '\x00', 10) }
    }
  }
)

test.register_message_test(
  "Capability off command switch off should be handled : dp 6",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { fifth_mock_child_device.id, { capability = "switch", component = "main", command = "off", args = { } } }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_parent_device.id, tuya_utils.build_send_tuya_command(mock_parent_device, '\x06', tuya_utils.DP_TYPE_BOOL, '\x00', 11) }
    }
  }
)

test.register_coroutine_test(
    "added lifecycle event should create children in parent device",
    function()
      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({ mock_base_device.id, "added" })
      mock_base_device:expect_device_create({
        type = "EDGE_CHILD",
        label = "Switch 2",
        profile = "basic-switch",
        parent_device_id = mock_base_device.id,
        parent_assigned_child_key = "02",
      })
      mock_base_device:expect_device_create({
        type = "EDGE_CHILD",
        label = "Switch 3",
        profile = "basic-switch",
        parent_device_id = mock_base_device.id,
        parent_assigned_child_key = "03"
      })
      mock_base_device:expect_device_create({
        type = "EDGE_CHILD",
        label = "Switch 4",
        profile = "basic-switch",
        parent_device_id = mock_base_device.id,
        parent_assigned_child_key = "04"
      })
      mock_base_device:expect_device_create({
        type = "EDGE_CHILD",
        label = "Switch 5",
        profile = "basic-switch",
        parent_device_id = mock_base_device.id,
        parent_assigned_child_key = "05"
      })
      mock_base_device:expect_device_create({
        type = "EDGE_CHILD",
        label = "Switch 6",
        profile = "basic-switch",
        parent_device_id = mock_base_device.id,
        parent_assigned_child_key = "06"
      })
    end
)

test.run_registered_tests()