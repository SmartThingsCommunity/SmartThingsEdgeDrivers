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
local capabilities = require "st.capabilities"
local Basic = (require "st.zwave.CommandClass.Basic")({version=1})
local t_utils = require "integration_test.utils"

-- supported comand classes
local sensor_endpoints = {
  {
    command_classes = {
      {value = zw.BASIC},
    }
  }
}

local mock_siren = test.mock_device.build_test_zwave_device({
    profile = t_utils.get_profile_definition("alarm-switch.yml"),
    zwave_endpoints = sensor_endpoints,
    zwave_manufacturer_id = 0x0084,
    zwave_product_type = 0x0313,
    zwave_product_id = 0x010B
})

local function test_init()
  test.mock_device.add_test_device(mock_siren)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Setting alarm both should generate correct zwave messages",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_siren.id,
        { capability = "alarm", command = "both", args = {} }
      }
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value=0xFF})
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({})
      )
    )
    test.socket.zwave:__queue_receive({
      mock_siren.id,
      Basic:Report( { value = 0xFF })
    })
    test.socket.capability:__expect_send(mock_siren:generate_test_message("main", capabilities.alarm.alarm.both({})))
    test.socket.capability:__expect_send(mock_siren:generate_test_message("main", capabilities.switch.switch.on({})))
  end
)


test.register_coroutine_test(
  "Setting alarm siren should generate correct zwave messages",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_siren.id,
        { capability = "alarm", command = "siren", args = {} }
      }
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value=0x42})
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({})
      )
    )
    test.socket.zwave:__queue_receive({
      mock_siren.id,
      Basic:Report( { value = 0x42 })
    })
    test.socket.capability:__expect_send(mock_siren:generate_test_message("main", capabilities.alarm.alarm.siren({})))
    test.socket.capability:__expect_send(mock_siren:generate_test_message("main", capabilities.switch.switch.on({})))
  end
)

test.register_coroutine_test(
  "Setting alarm strobe should generate correct zwave messages",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_siren.id,
        { capability = "alarm", command = "strobe", args = {} }
      }
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value=0x21})
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({})
      )
    )
    test.socket.zwave:__queue_receive({
      mock_siren.id,
      Basic:Report( { value = 0x21 })
    })
    test.socket.capability:__expect_send(mock_siren:generate_test_message("main", capabilities.alarm.alarm.strobe({})))
    test.socket.capability:__expect_send(mock_siren:generate_test_message("main", capabilities.switch.switch.on({})))
  end
)

test.register_coroutine_test(
  "Setting alarm off should generate correct zwave messages",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_siren.id,
        { capability = "alarm", command = "off", args = {} }
      }
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Set({value=0x00})
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_siren,
        Basic:Get({})
      )
    )
    test.socket.zwave:__queue_receive({
      mock_siren.id,
      Basic:Report( { value = 0x00 })
    })
    test.socket.capability:__expect_send(mock_siren:generate_test_message("main", capabilities.alarm.alarm.off({})))
    test.socket.capability:__expect_send(mock_siren:generate_test_message("main", capabilities.switch.switch.off({})))
  end
)

test.run_registered_tests()