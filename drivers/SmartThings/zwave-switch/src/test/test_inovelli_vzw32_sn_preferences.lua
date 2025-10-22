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
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local Configuration = (require "st.zwave.CommandClass.Configuration")({version=4})
local Association = (require "st.zwave.CommandClass.Association")({version=1})
local t_utils = require "integration_test.utils"
local utils = require "st.utils"
local json = require "st.json"

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

-- Create mock device
local mock_inovelli_vzw32_sn = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("inovelli-mmwave-dimmer-vzw32-sn.yml"),
  zwave_endpoints = inovelli_vzw32_sn_endpoints,
  zwave_manufacturer_id = INOVELLI_MANUFACTURER_ID,
  zwave_product_type = INOVELLI_VZW32_SN_PRODUCT_TYPE,
  zwave_product_id = INOVELLI_VZW32_SN_PRODUCT_ID
})

local function test_init()
  test.mock_device.add_test_device(mock_inovelli_vzw32_sn)
end
test.set_test_init_function(test_init)

-- Test preference change for notification child creation
test.register_message_test(
  "Enabling notification child preference should create child device",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_inovelli_vzw32_sn.id, "added" },
    },
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = {
        mock_inovelli_vzw32_sn.id,
        "infoChanged",
        json.encode({
          old_st_store = {
            preferences = {
              notificationChild = false
            }
          },
          preferences = {
            notificationChild = true
          }
        })
      }
    },
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_inovelli_vzw32_sn.id, "device_created" },
    },
  },
  {
    inner_block_ordering = "relaxed"
  }
)

-- Test preference change for configuration parameters
test.register_message_test(
  "Changing configuration preference should send Configuration Set command",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_inovelli_vzw32_sn.id, "added" },
    },
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = {
        mock_inovelli_vzw32_sn.id,
        "infoChanged",
        json.encode({
          old_st_store = {
            preferences = {
              ledIntensity = 50
            }
          },
          preferences = {
            ledIntensity = 75
          }
        })
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_inovelli_vzw32_sn,
        Configuration:Set({
          parameter_number = 1, -- Example parameter number
          configuration_value = 75,
          size = 1
        })
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_inovelli_vzw32_sn,
        Association:Set({
          grouping_identifier = 1,
          node_ids = {1} -- Mock hub Z-Wave ID
        })
      )
    },
  },
  {
    inner_block_ordering = "relaxed"
  }
)

-- Test multiple preference changes
test.register_message_test(
  "Multiple preference changes should send multiple Configuration Set commands",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_inovelli_vzw32_sn.id, "added" },
    },
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = {
        mock_inovelli_vzw32_sn.id,
        "infoChanged",
        json.encode({
          old_st_store = {
            preferences = {
              ledIntensity = 50,
              ledColorWhenOn = 1,
              ledColorWhenOff = 2
            }
          },
          preferences = {
            ledIntensity = 75,
            ledColorWhenOn = 3,
            ledColorWhenOff = 4
          }
        })
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_inovelli_vzw32_sn,
        Configuration:Set({
          parameter_number = 1,
          configuration_value = 75,
          size = 1
        })
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_inovelli_vzw32_sn,
        Configuration:Set({
          parameter_number = 2,
          configuration_value = 3,
          size = 1
        })
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_inovelli_vzw32_sn,
        Configuration:Set({
          parameter_number = 3,
          configuration_value = 4,
          size = 1
        })
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_inovelli_vzw32_sn,
        Association:Set({
          grouping_identifier = 1,
          node_ids = {1}
        })
      )
    },
  },
  {
    inner_block_ordering = "relaxed"
  }
)

-- Test boolean preference handling
test.register_message_test(
  "Boolean preference should be converted to numeric value",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_inovelli_vzw32_sn.id, "added" },
    },
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = {
        mock_inovelli_vzw32_sn.id,
        "infoChanged",
        json.encode({
          old_st_store = {
            preferences = {
              ledEnabled = false
            }
          },
          preferences = {
            ledEnabled = true
          }
        })
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_inovelli_vzw32_sn,
        Configuration:Set({
          parameter_number = 4,
          configuration_value = 1, -- true converted to 1
          size = 1
        })
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_inovelli_vzw32_sn,
        Association:Set({
          grouping_identifier = 1,
          node_ids = {1}
        })
      )
    },
  },
  {
    inner_block_ordering = "relaxed"
  }
)

-- Test signed integer preference handling
test.register_message_test(
  "Large signed integer preference should be handled correctly",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_inovelli_vzw32_sn.id, "added" },
    },
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = {
        mock_inovelli_vzw32_sn.id,
        "infoChanged",
        json.encode({
          old_st_store = {
            preferences = {
              largeValue = 100
            }
          },
          preferences = {
            largeValue = 3000000000 -- Large value that would overflow 32-bit signed int
          }
        })
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_inovelli_vzw32_sn,
        Configuration:Set({
          parameter_number = 5,
          configuration_value = -1294967296, -- Correctly calculated signed value
          size = 4
        })
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_inovelli_vzw32_sn,
        Association:Set({
          grouping_identifier = 1,
          node_ids = {1}
        })
      )
    },
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.run_registered_tests()