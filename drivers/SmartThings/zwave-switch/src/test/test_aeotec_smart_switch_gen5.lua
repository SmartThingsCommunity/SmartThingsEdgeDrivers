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
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 1 })
local t_utils = require "integration_test.utils"

local switch_endpoints = {
  {
    command_classes = {
      {value = zw.BASIC},
      {value = zw.CONFIGURATION},
      {value = zw.SWITCH_BINARY}
    }
  }
}

local mock_switch = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("metering-switch.yml"),
  zwave_endpoints = switch_endpoints,
  zwave_manufacturer_id = 0x0086,
  zwave_product_type = 0x0103,
  zwave_product_id = 0x004B,
})

local function test_init()
  test.mock_device.add_test_device(mock_switch)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
    "doConfigure lifecycle event should generate the correct commands",
    function ()
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({ mock_switch.id, "doConfigure" })
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_switch,
          Configuration:Set({ parameter_number = 101, configuration_value = 8, size = 4 })
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_switch,
          Configuration:Set({ parameter_number = 111, configuration_value = 300, size = 4 })
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_switch,
          Configuration:Set({ parameter_number = 102, configuration_value = 0, size = 4 })
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_switch,
          Configuration:Set({ parameter_number = 103, configuration_value = 0, size = 4 })
      ))
      mock_switch:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
)

test.run_registered_tests()
