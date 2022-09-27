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
local capabilities = require "st.capabilities"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version=2 })

local zwave_switch_profile = {
  components = {
    main = {
      capabilities = {
        [capabilities.switch.ID] = { id = capabilities.switch.ID },
      },
      id = "main",
    },
    ["switch1"] = {
      capabilities = {
        [capabilities.switch.ID] = { id = capabilities.switch.ID },
      },
      id = "switch1",
    },
    ["switch2"] = {
      capabilities = {
        [capabilities.switch.ID] = { id = capabilities.switch.ID },
      },
      id = "switch2",
    },
    ["switch3"] = {
      capabilities = {
        [capabilities.switch.ID] = { id = capabilities.switch.ID },
      },
      id = "switch3",
    },
    ["switch4"] = {
      capabilities = {
        [capabilities.switch.ID] = { id = capabilities.switch.ID },
      },
      id = "switch4",
    },
    ["switch5"] = {
      capabilities = {
        [capabilities.switch.ID] = { id = capabilities.switch.ID },
      },
      id = "switch5",
    },
  }
}

-- supported comand classes: SWITCH_BINARY
local switch_endpoints = {
  {
    command_classes = {
      {value = zw.SWITCH_BINARY}
    }
  },
  {
    command_classes = {
      {value = zw.SWITCH_BINARY}
    }
  },
  {
    command_classes = {
      {value = zw.SWITCH_BINARY}
    }
  },
  {
    command_classes = {
      {value = zw.SWITCH_BINARY}
    }
  },
  {
    command_classes = {
      {value = zw.SWITCH_BINARY}
    }
  }
}

local mock_switch = test.mock_device.build_test_zwave_device({
  profile = zwave_switch_profile,
  zwave_endpoints = switch_endpoints,
  zwave_manufacturer_id = 0x027A, -- aka mfr
  zwave_product_type = 0xA000, -- aka product; aka prod
  zwave_product_id = 0xA004, -- aka model
})

local zwave_binary_switch_on_report_ch_0 = zw_test_utils.zwave_test_build_receive_command(
  SwitchBinary:Report(
    {current_value=0xFF},
    {
      encap = zw.ENCAP.AUTO,
      src_channel = 0,
      dst_channels = {0}
    }
  )
)

local zwave_binary_switch_on_report_ch_2 = zw_test_utils.zwave_test_build_receive_command(
  SwitchBinary:Report(
    {current_value=0xFF},
    {
      encap = zw.ENCAP.AUTO,
      src_channel = 2,
      dst_channels = {0}
    }
  )
)

local function test_init()
  test.mock_device.add_test_device(mock_switch)
end


test.set_test_init_function(test_init)

test.register_message_test(
    "Binary switch on/off report from channel 2 should be handled: on",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_switch.id, "init" },
      },
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_switch.id, zwave_binary_switch_on_report_ch_2 }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_switch:generate_test_message("switch2", capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
    "Binary switch on/off report from channel 0 should be handled: on",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_switch.id, "init" },
      },
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_switch.id, zwave_binary_switch_on_report_ch_0 }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_switch:generate_test_message("main", capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
    "Multichannel switch on/off capability command on component 2 should be handled: on",
    {
      {
        channel = "capability",
        direction = "receive",
        message = {
          mock_switch.id,
          { capability = "switch", command = "on", component = "switch2", args = {} }
        }
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
          mock_switch,
          SwitchBinary:Set({ target_value=SwitchBinary.value.ON_ENABLE },
            {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {2}})
        )
      }
    }
)

test.register_message_test(
    "Multichannel switch on/off capability command on component [main] should be handled: on",
    {
      {
        channel = "capability",
        direction = "receive",
        message = {
          mock_switch.id,
          { capability = "switch", command = "on", component = "main", args = {} }
        }
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
          mock_switch,
          SwitchBinary:Set({ target_value=SwitchBinary.value.ON_ENABLE },
            {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {}})
        )
      }
    }
)

test.run_registered_tests()
