-- Copyright 2023 SmartThings
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
local t_utils = require "integration_test.utils"
local zw_test_utils = require "integration_test.zwave_test_utils"
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version = 2, strict = true })

-- supported comand classes
local switch_endpoints = {
  {
    command_classes = {
      { value = zw.BASIC },
      { value = zw.SWITCH_BINARY }
    },
  },
  {
    command_classes = {
      { value = zw.BASIC },
      { value = zw.SWITCH_BINARY }
    }
  },
  {
    command_classes = {
      { value = zw.BASIC },
      { value = zw.SWITCH_BINARY }
    }
  }
}

local mock_parent = test.mock_device.build_test_zwave_device({
  label = "Aeotec Switch 1",
  profile = t_utils.get_profile_definition("switch-binary.yml"),
  zwave_endpoints = switch_endpoints,
  zwave_manufacturer_id = 0x0086,
  zwave_product_type = 0x0103,
  zwave_product_id = 0x008C,
  child_ids = {
    "abcdefghijklmnopq",
    "12345678910111213"
  }
})

local mock_parent_no_data = test.mock_device.build_test_zwave_device({
  label = "Aeotec Switch 1",
  profile = t_utils.get_profile_definition("switch-binary.yml"),
  zwave_endpoints = switch_endpoints,
  zwave_manufacturer_id = 0x0086,
  zwave_product_type = 0x0103,
  zwave_product_id = 0x008C
})

local function test_init()
  test.mock_device.add_test_device(mock_parent)
  test.mock_device.add_test_device(mock_parent_no_data)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Adding a device that already has childen should not create more",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_parent.id, "added" })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
          mock_parent,
          SwitchBinary:Get({}, {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels = { 1 }
          })
      )
    )
  end
)

test.register_coroutine_test(
  "Adding a device that doesn't have childen should create more",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_parent_no_data.id, "added" })
    mock_parent_no_data:expect_device_create({
      type = "EDGE_CHILD",
      label = "Aeotec Switch 2",
      profile = "switch-binary",
      parent_device_id = mock_parent_no_data.id,
      parent_assigned_child_key = "02"
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
          mock_parent_no_data,
          SwitchBinary:Get({}, {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels = { 1 }
          })
      )
    )
  end
)

test.run_registered_tests()
