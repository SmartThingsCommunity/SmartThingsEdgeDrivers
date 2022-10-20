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
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version = 2, strict = true })
local t_utils = require "integration_test.utils"

-- supported command classes
local switch_endpoints = {
  {
    command_classes = {
      { value = zw.MULTI_CHANNEL }
    }
  },
  {
    command_classes = {
      { value = zw.MULTI_CHANNEL }
    }
  },
  {
    command_classes = {
      { value = zw.MULTI_CHANNEL }
    }
  }
}

local mock_parent = test.mock_device.build_test_zwave_device({
  label = "Z-Wave Switch Multichannel",
  profile = t_utils.get_profile_definition("switch-binary.yml"),
  zwave_endpoints = switch_endpoints
})

local mock_child = test.mock_device.build_test_child_device({
  profile = t_utils.get_profile_definition("switch-binary.yml"),
  parent_device_id = mock_parent.id,
  parent_assigned_child_key = string.format("%02X", 2)
})

local function test_init()
  test.mock_device.add_test_device(mock_parent)
  test.mock_device.add_test_device(mock_child)
end

test.set_test_init_function(test_init)

test.register_message_test(
    "Device Added handler should be generate wakeup interval set command",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "init" }
      },
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "added" }
      },
      --{
      --  channel = "zwave",
      --  direction = "send",
      --  message = zw_test_utils.zwave_test_build_send_command(
      --      mock_sensor,
      --      WakeUp:IntervalSet({node_id = 0x00, seconds = 1200})
      --  )
      --}
    }
)
test.run_registered_tests()