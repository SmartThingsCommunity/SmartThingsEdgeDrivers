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
local t_utils = require "integration_test.utils"
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })

local button_endpoints = {
    {
        command_classes = {
            {value = zw.CENTRAL_SCENE},
            {value = zw.NOTIFICATION},
            {value = zw.BATTERY}
        }
    }
}

local mock_aeotec_nanomote_one = test.mock_device.build_test_zwave_device({
    profile = t_utils.get_profile_definition("button-generic.yml"),
    zwave_endpoints = button_endpoints,
    zwave_manufacturer_id = 0x0371,
    zwave_product_type = 0x0102,
    zwave_product_id = 0x0004
})

local function  test_init()
    test.mock_device.add_test_device(mock_aeotec_nanomote_one)
end
test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Aeotec nanomote one's supported button values",
  function()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_aeotec_nanomote_one.id, "added" })

    test.socket.capability:__expect_send(
      mock_aeotec_nanomote_one:generate_test_message(
        "main",
        capabilities.button.supportedButtonValues({"pushed", "held", "down_hold"}, {visibility = { displayed = false }})
      )
    )
    test.socket.capability:__expect_send(
      mock_aeotec_nanomote_one:generate_test_message(
        "main",
        capabilities.button.numberOfButtons({ value = 1 }, {visibility = { displayed = false }})
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_aeotec_nanomote_one,
        Battery:Get({})
      )
    )
  end
)

test.run_registered_tests()
