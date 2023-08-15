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
local Battery = (require "st.zwave.CommandClass.Battery")({version=1})
local Association = (require "st.zwave.CommandClass.Association")({version=2})
local SensorBinary = (require "st.zwave.CommandClass.SensorBinary")({version=2})
local WakeUp = (require "st.zwave.CommandClass.WakeUp")({version=1})
local t_utils = require "integration_test.utils"

local sensor_endpoints = {
  {
    command_classes = {
      {value = zw.BATTERY},
      {value = zw.NOTIFICATION},
      {value = zw.SENSOR_MULTILEVEL},
      {value = zw.WAKE_UP}
    }
  }
}

local mock_sensor = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("motion-battery-tamper.yml"),
  zwave_endpoints = sensor_endpoints,
  zwave_manufacturer_id = 0x011A,
  zwave_product_type = 0x0601,
  zwave_product_id = 0x0901,
})

local function test_init()
  test.mock_device.add_test_device(mock_sensor)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
    "lifecycle configure event should configure device",
    function ()
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({ mock_sensor.id, "doConfigure" })
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Battery:Get({})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Association:Set({grouping_identifier = 1, node_ids = {}})
      ))
      mock_sensor:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
)

test.register_coroutine_test(
    "At a WakeUp, Assocation:Set should be sent when there wasn't a motion status event",
    function()
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.zwave:__queue_receive({mock_sensor.id, WakeUp:Notification({}) })
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          WakeUp:IntervalGet({})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Association:Set({grouping_identifier = 1, node_ids = {}})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Battery:Get({})
      ))
    end
)

test.register_coroutine_test(
    "At a WakeUp, Assocation:Set shouldn't be sent when there was a motion status event",
    function()
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.zwave:__queue_receive({mock_sensor.id, SensorBinary:Report({sensor_type=SensorBinary.sensor_type.MOTION, sensor_value=0x00})})
      test.socket.capability:__expect_send(mock_sensor:generate_test_message("main", capabilities.motionSensor.motion.inactive()))
      test.socket.zwave:__queue_receive({mock_sensor.id, WakeUp:Notification({}) })
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          Battery:Get({})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_sensor,
          WakeUp:IntervalGet({})
      ))

    end
)


test.run_registered_tests()
