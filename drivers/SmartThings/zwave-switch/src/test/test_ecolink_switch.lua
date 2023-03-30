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
local t_utils = require "integration_test.utils"
local capabilities = require "st.capabilities"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"

local Basic = (require "st.zwave.CommandClass.Basic")({ version=1 })
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version=2 })
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })


local ecolink_switch_endpoints = {
  {
    command_classes = {
      { value = zw.BASIC },
      { value = zw.SWITCH_BINARY },
      { value = zw.BATTERY }
    }
  }
}

local mock_device = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("switch-battery.yml"),
  zwave_endpoints = ecolink_switch_endpoints,
  zwave_manufacturer_id = 0x014A,
  zwave_product_type = 0x0006,
  zwave_product_id = 0x0002
})

local function test_init()
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

test.register_message_test(
  "Device should be polled with refresh right after inclusion",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "added" }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Battery:Get({})
      )
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
  "Refresh Capability Command should refresh device",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { mock_device.id, { capability = "refresh", command = "refresh", args = {} }}
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Battery:Get({})
      )
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
  "Battery report should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Battery:Report({ battery_level = 0x63 })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.battery.battery(99))
    }
  }
)

test.register_message_test(
  "Switch Binary report ON_ENABLE should be handled by main component",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          SwitchBinary:Report({ current_value = SwitchBinary.value.ON_ENABLE })
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.on())
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
  "Switch Binary report OFF_DISABLE should be handled by main component",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          SwitchBinary:Report({ current_value = SwitchBinary.value.OFF_DISABLE })
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.off())
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
  "Basic report (0xFF) should be handled by main component",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          Basic:Report({value = 0xFF})
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.on())
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
  "Basic report (0x00) should be handled by main component",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          Basic:Report({value = 0x00})
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.off())
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
  "Basic SET 0xFF should be handled as switch on",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          Basic:Set({value = 0xFF})
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.on())
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
  "Basic SET 0x00 should be handled as switch off",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          Basic:Set({value = 0x00})
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.off())
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.run_registered_tests()
