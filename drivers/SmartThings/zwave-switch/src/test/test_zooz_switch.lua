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

local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=4 })
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version = 2 })
local Meter = (require "st.zwave.CommandClass.Meter")({ version = 3 })

local zooz_switch_endpoints = {
  {
    command_classes = {
      { value = zw.BASIC },
      { value = zw.SWITCH_BINARY },
      { value = zw.METER }
    }
  }
}

local mock_device = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("dual-metering-switch.yml"),
  zwave_endpoints = zooz_switch_endpoints,
  zwave_manufacturer_id = 0x027A,
  zwave_product_type = 0xA000,
  zwave_product_id = 0xA003
})

local function test_init()
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Device should be configured",
  function()
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({mock_device.id, "doConfigure"})
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_device,
      Configuration:Set({
        parameter_number = 2,
        size = 4,
        configuration_value = 10
      })
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_device,
      Configuration:Set({
        parameter_number = 3,
        size = 4,
        configuration_value = 600
      })
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_device,
      Configuration:Set({
        parameter_number = 4,
        size = 4,
        configuration_value = 600
      })
    ))
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_coroutine_test(
  "Refresh capability should evoke the correct Z-Wave GETs",
  function()
    test.socket.zwave:__set_channel_ordering('relaxed')
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "refresh", component = "main", command = "refresh", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={1}
          })
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={2}
          })
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Meter:Get(
          {scale = Meter.scale.electric_meter.KILOWATT_HOURS},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={1}
          }
        )
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Meter:Get(
          {scale = Meter.scale.electric_meter.WATTS},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={1}
          }
        )
      )
     )
     test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Meter:Get({scale = Meter.scale.electric_meter.KILOWATT_HOURS},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={2}
          }
        )
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Meter:Get(
          {scale = Meter.scale.electric_meter.WATTS},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={2}
          })
      )
    )
  end
)

test.run_registered_tests()
