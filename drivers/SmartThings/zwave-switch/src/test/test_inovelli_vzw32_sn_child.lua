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
local capabilities = require "st.capabilities"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local Configuration = (require "st.zwave.CommandClass.Configuration")({version=4})
local t_utils = require "integration_test.utils"
local st_device = require "st.device"

-- Inovelli VZW32-SN device identifiers
local INOVELLI_MANUFACTURER_ID = 0x031E
local INOVELLI_VZW32_SN_PRODUCT_TYPE = 0x0017
local INOVELLI_VZW32_SN_PRODUCT_ID = 0x0001

-- Device endpoints with supported command classes
local inovelli_vzw32_sn_endpoints = {
  {
    command_classes = {
      {value = zw.SWITCH_BINARY},
      {value = zw.SWITCH_MULTILEVEL},
      {value = zw.BASIC},
      {value = zw.CONFIGURATION},
      {value = zw.CENTRAL_SCENE},
      {value = zw.ASSOCIATION},
    }
  }
}

-- Create mock parent device
local mock_parent_device = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("inovelli-mmwave-dimmer-vzw32-sn.yml"),
  zwave_endpoints = inovelli_vzw32_sn_endpoints,
  zwave_manufacturer_id = INOVELLI_MANUFACTURER_ID,
  zwave_product_type = INOVELLI_VZW32_SN_PRODUCT_TYPE,
  zwave_product_id = INOVELLI_VZW32_SN_PRODUCT_ID
})

-- Create mock child device (notification device)
local mock_child_device = test.mock_device.build_test_device({
  profile = t_utils.get_profile_definition("rgbw-bulb-2700K-6500K.yml"),
  parent_device_id = mock_parent_device.id,
  parent_assigned_child_key = "notification"
})

-- Set child device network type
mock_child_device.network_type = st_device.NETWORK_TYPE_CHILD

local function test_init()
  test.mock_device.add_test_device(mock_parent_device)
  test.mock_device.add_test_device(mock_child_device)
end
test.set_test_init_function(test_init)

-- Test child device initialization
test.register_message_test(
  "Child device should initialize with default color values",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_child_device.id, "added" },
    },
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = mock_child_device:generate_test_message("main", capabilities.colorControl.hue(1))
    },
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = mock_child_device:generate_test_message("main", capabilities.colorControl.saturation(1))
    },
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = mock_child_device:generate_test_message("main", capabilities.colorTemperature.colorTemperature(6500))
    },
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = mock_child_device:generate_test_message("main", capabilities.switchLevel.level(100))
    },
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = mock_child_device:generate_test_message("main", capabilities.switch.switch("off"))
    },
  },
  {
    inner_block_ordering = "relaxed"
  }
)

-- Test child device switch on command
test.register_message_test(
  "Child device switch on should emit events and send configuration to parent",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_child_device.id,
        { capability = "switch", command = "on", args = {} }
      }
    },
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = mock_child_device:generate_test_message("main", capabilities.switch.switch("on"))
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_parent_device,
        Configuration:Set({
          parameter_number = 99,
          configuration_value = 0, -- This would be calculated based on notification value
          size = 4
        })
      )
    },
  },
  {
    inner_block_ordering = "relaxed"
  }
)

-- Test child device switch off command
test.register_message_test(
  "Child device switch off should emit events and send configuration to parent",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_child_device.id,
        { capability = "switch", command = "off", args = {} }
      }
    },
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = mock_child_device:generate_test_message("main", capabilities.switch.switch("off"))
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_parent_device,
        Configuration:Set({
          parameter_number = 99,
          configuration_value = 0,
          size = 4
        })
      )
    },
  },
  {
    inner_block_ordering = "relaxed"
  }
)

-- Test child device level command
test.register_message_test(
  "Child device level command should emit events and send configuration to parent",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_child_device.id,
        { capability = "switchLevel", command = "setLevel", args = { level = 75 } }
      }
    },
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = mock_child_device:generate_test_message("main", capabilities.switchLevel.level(75))
    },
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = mock_child_device:generate_test_message("main", capabilities.switch.switch("on"))
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_parent_device,
        Configuration:Set({
          parameter_number = 99,
          configuration_value = 0, -- This would be calculated based on notification value
          size = 4
        })
      )
    },
  },
  {
    inner_block_ordering = "relaxed"
  }
)

-- Test child device color command
test.register_message_test(
  "Child device color command should emit events and send configuration to parent",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_child_device.id,
        { capability = "colorControl", command = "setColor", args = { color = { hue = 200, saturation = 80 } } }
      }
    },
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = mock_child_device:generate_test_message("main", capabilities.colorControl.hue(200))
    },
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = mock_child_device:generate_test_message("main", capabilities.colorControl.saturation(80))
    },
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = mock_child_device:generate_test_message("main", capabilities.switch.switch("on"))
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_parent_device,
        Configuration:Set({
          parameter_number = 99,
          configuration_value = 0, -- This would be calculated based on notification value
          size = 4
        })
      )
    },
  },
  {
    inner_block_ordering = "relaxed"
  }
)

-- Test child device color temperature command
test.register_message_test(
  "Child device color temperature command should emit events and send configuration to parent",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_child_device.id,
        { capability = "colorTemperature", command = "setColorTemperature", args = { temperature = 3000 } }
      }
    },
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = mock_child_device:generate_test_message("main", capabilities.colorControl.hue(100))
    },
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = mock_child_device:generate_test_message("main", capabilities.colorTemperature.colorTemperature(3000))
    },
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = mock_child_device:generate_test_message("main", capabilities.switch.switch("on"))
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_parent_device,
        Configuration:Set({
          parameter_number = 99,
          configuration_value = 0, -- This would be calculated based on notification value
          size = 4
        })
      )
    },
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.run_registered_tests()
