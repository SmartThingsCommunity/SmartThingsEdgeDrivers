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
local Basic = (require "st.zwave.CommandClass.Basic")({version=1})
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
local t_utils = require "integration_test.utils"

-- supported comand classes
local sensor_endpoints = {
  {
    command_classes = {
      {value = zw.BASIC},
      {value = zw.BATTERY}
    }
  }
}

local mock_siren = test.mock_device.build_test_zwave_device({
    profile = t_utils.get_profile_definition("alarm-battery.yml"),
    zwave_endpoints = sensor_endpoints,
    zwave_manufacturer_id = 0x0060,
    zwave_product_type = 0x000C,
    zwave_product_id = 0x0001
})

local function test_init()
  test.mock_device.add_test_device(mock_siren)
end

test.set_test_init_function(test_init)

test.register_message_test(
  "Battery 0% report should be ignored",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_siren.id, zw_test_utils.zwave_test_build_receive_command(Battery:Report({ battery_level = 0x00 })) }
    }
  }
)

test.register_coroutine_test(
  "Siren should refresh attributes when added",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.zwave:__set_channel_ordering('relaxed')
    test.socket.device_lifecycle:__queue_receive({ mock_siren.id, "added" })
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_siren,
      Basic:Get({})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_siren,
      Battery:Get({})
    ))
  end
)

test.run_registered_tests()
