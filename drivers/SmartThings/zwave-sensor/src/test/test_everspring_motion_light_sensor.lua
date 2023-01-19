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
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({version=2,strict=true})
local SensorBinary = (require "st.zwave.CommandClass.SensorBinary")({version=2})
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })
local t_utils = require "integration_test.utils"

local sensor_endpoints = {
  {
    command_classes = {
      {value = zw.NOTIFICATION},
      {value = zw.SENSOR_MULTILEVEL},
      {value = zw.SWITCH_BINARY},
    }
  }
}

local mock_sensor = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("motion-light.yml"),
  zwave_endpoints = sensor_endpoints,
  zwave_manufacturer_id = 0x0060,
  zwave_product_type = 0x0012,
  zwave_product_id = 0x0001,
})

local function test_init()
  test.mock_device.add_test_device(mock_sensor)
end

test.set_test_init_function(test_init)

test.register_message_test(
  "Added lifecycle event should be handled",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_sensor.id, "added" }
    },
    -- {
    --   channel = "capability",
    --   direction = "send",
    --   message = mock_sensor:generate_test_message("main", capabilities.motionSensor.motion.inactive())
    -- },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_sensor,
        SwitchBinary:Get({})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_sensor,
        SensorBinary:Get({ sensor_type = SensorBinary.sensor_type.MOTION })
      )
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.run_registered_tests()
