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
local constants = require "st.zwave.constants"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({ version=4 })
local t_utils = require "integration_test.utils"

-- supported comand classes: SWITCH_MULTILEVEL
local window_shade_switch_multilevel_endpoints = {
  {
    command_classes = {
      {value = zw.SWITCH_MULTILEVEL}
    }
  }
}

local mock_springs_window_fashion_shade = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("base-window-treatment.yml"),
  zwave_endpoints = window_shade_switch_multilevel_endpoints,
  zwave_manufacturer_id = 0x026E,
  zwave_product_type = 0x4353,
  zwave_product_id = 0x5A31,
})

local function test_init()
  test.mock_device.add_test_device(mock_springs_window_fashion_shade)
end
test.set_test_init_function(test_init)

test.register_coroutine_test(
    "Setting window shade preset generate correct zwave messages",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_springs_window_fashion_shade.id,
            { capability = "windowShadePreset", command = "presetPosition", args = {} }
          }
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_springs_window_fashion_shade,
            SwitchMultilevel:Set({
                value = SwitchMultilevel.value.ON_ENABLE,
                duration = constants.DEFAULT_DIMMING_DURATION
              })
          )
      )
      test.wait_for_events()

      test.mock_time.advance_time(5)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_springs_window_fashion_shade,
            SwitchMultilevel:Get({})
          )
      )
    end
)

test.run_registered_tests()
