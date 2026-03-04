-- Copyright 2026 SmartThings
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
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
local zw_test_utils = require "integration_test.zwave_test_utils"
local t_utils = require "integration_test.utils"
local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass.Version
local Version = (require "st.zwave.CommandClass.Version")({ version = 1 })
--- @type st.zwave.CommandClass.WakeUp
local WakeUp = (require "st.zwave.CommandClass.WakeUp")({ version = 1 })
--- @type st.zwave.CommandClass.Battery
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })

local sensor_endpoints = {
  {
    command_classes = {
      { value = cc.WAKE_UP },
      { value = cc.BATTERY },
    }
  }
}

local mock_device = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("zooz-zse42-water.yml"),
  zwave_endpoints = sensor_endpoints,
  zwave_manufacturer_id = 0x027A,
  zwave_product_type = 0x7000,
  zwave_product_id = 0xE002,
})

local function test_init()
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

test.register_message_test(
      "Wakeup notification should not poll binary sensor if device has contact state",
      {
        {
          channel = "zwave",
          direction = "receive",
          message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(WakeUp:Notification({ })) }
        },
        --This is sent by the sub-driver
        {
          channel = "zwave",
          direction = "send",
          message = zw_test_utils.zwave_test_build_send_command(
                mock_device,
                Version:Get({})
          )
        },
        --This is sent by the main driver
        {
          channel = "zwave",
          direction = "send",
          message = zw_test_utils.zwave_test_build_send_command(
                mock_device,
                WakeUp:IntervalGetV1({})
          )
        },
        --This is sent by the main driver
        {
          channel = "zwave",
          direction = "send",
          message = zw_test_utils.zwave_test_build_send_command(
                mock_device,
                Battery:Get({ })
          )
        },
      },
      {
        inner_block_ordering = "relaxed"
      }
)

test.register_message_test(
  "Version:Report should emit firmwareUpdate.currentVersion",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Version:Report({
        application_version = 1,
        application_sub_version = 5,
      })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.firmwareUpdate.currentVersion({ value = "1.05" }))
    }
  }
)

test.register_coroutine_test(
  "added lifecycle event should emit initial state and request firmware version",
  function ()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.waterSensor.water.dry())
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(mock_device, Version:Get({}))
    )
  end
)

test.run_registered_tests()