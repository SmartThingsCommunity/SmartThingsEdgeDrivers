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
local capabilities = require "st.capabilities"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({version=2})
local Meter = (require "st.zwave.CommandClass.Meter")({version=3})

-- supported comand classes: SWITCH_BINARY
local qubino_flush_2_relay_endpoints = {
  {
    command_classes = {
      {value = zw.SWITCH_BINARY},
      {value = zw.METER},
    }
  }
}

local mock_qubino_flush_2_relay = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("qubino-flush2-relay-temperature.yml"),
  zwave_endpoints = qubino_flush_2_relay_endpoints
})

local function test_init()
  test.mock_device.add_test_device(mock_qubino_flush_2_relay)
end
test.set_test_init_function(test_init)

test.register_message_test(
    "Energy meter report should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_qubino_flush_2_relay.id, zw_test_utils.zwave_test_build_receive_command(Meter:Report({
          scale = Meter.scale.electric_meter.KILOWATT_HOURS,
          meter_value = 5})
        )}
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_qubino_flush_2_relay:generate_test_message("main", capabilities.energyMeter.energy({ value = 5, unit = "kWh" }))
      }
    }
)

test.register_coroutine_test(
  "Refresh sends commands to all components including base device",
  function()
    -- refresh commands for zwave devices do not have guaranteed ordering
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_qubino_flush_2_relay,
        SwitchBinary:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels = {}
          })
      ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_qubino_flush_2_relay,
        SwitchBinary:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels = {2}
          })
      ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_qubino_flush_2_relay,
        Meter:Get({scale = Meter.scale.electric_meter.KILOWATT_HOURS},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels = {}
          })
      ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_qubino_flush_2_relay,
        Meter:Get({scale = Meter.scale.electric_meter.WATTS},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels = {}
          })
      ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_qubino_flush_2_relay,
        Meter:Get({scale = Meter.scale.electric_meter.KILOWATT_HOURS},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels = {2}
          })
      ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_qubino_flush_2_relay,
        Meter:Get({scale = Meter.scale.electric_meter.WATTS},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels = {2}
          })
      ))
    --[[
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_qubino_flush_2_relay,
        SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.TEMPERATURE},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels = {???}
          })
      ))
    ]]
    test.socket.capability:__queue_receive({
      mock_qubino_flush_2_relay.id,
      { capability = "refresh", component = "main", command = "refresh", args = { } }
    })

  end
)

test.run_registered_tests()
