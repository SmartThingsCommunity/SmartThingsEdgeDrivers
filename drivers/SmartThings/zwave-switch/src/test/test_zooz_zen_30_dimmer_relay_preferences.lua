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
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 4 })

local preferencesMap = require "preferences"

local zooz_zen_dimmer_relay_endpoints = {
  {
    command_classes = {
      { value = zw.SWITCH_BINARY },
      { value = zw.SWITCH_MULTILEVEL },
      { value = zw.CENTRAL_SCENE }
    }
  },
  {
    command_classes = {
      { value = zw.SWITCH_BINARY }
    }
  }
}

local zooz_zen_dimmer_relay = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("zooz-zen-30-dimmer-relay.yml"),
  zwave_endpoints = zooz_zen_dimmer_relay_endpoints,
  zwave_manufacturer_id = 0x027A,
  zwave_product_type = 0xA000,
  zwave_product_id = 0xA008
})

local function test_init()
  test.mock_device.add_test_device(zooz_zen_dimmer_relay)
end
test.set_test_init_function(test_init)

do
  local new_param_value = 1
  local default_one = {
    [5] = true,
    [6] = true,
    [7] = true,
    [13] = true,
    [14] = true,
    [19] = true,
    [20] = true,
  }
  test.register_coroutine_test(
    "Parameter should be updated in the device configuration after change",
    function()
      local parameters = preferencesMap.get_device_parameters(zooz_zen_dimmer_relay)
      test.socket.zwave:__set_channel_ordering("relaxed")
      local newPreferences = {}
      for id, value in pairs(parameters) do
        if default_one[value.parameter_number] then
          newPreferences[id] = 0
        else
          newPreferences[id] = new_param_value
        end
        test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            zooz_zen_dimmer_relay,
            Configuration:Set({
              parameter_number = value.parameter_number,
              configuration_value = newPreferences[id],
              size = value.size
            })
          )
        )
      end
      test.socket.device_lifecycle:__queue_receive(
        zooz_zen_dimmer_relay:generate_info_changed({
          preferences = newPreferences
        })
      )
      test.wait_for_events()
    end
  )
end

test.run_registered_tests()
