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
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })
local t_utils = require "integration_test.utils"

local sensor_endpoints = {
  {
    command_classes =
    {
      {value = zw.BASIC}
    }
  }
}

local mock_device = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("switch-binary.yml"),
  zwave_endpoints = sensor_endpoints,
  zwave_manufacturer_id = 0x001A,
  zwave_product_type = 0x4243,
  zwave_product_id = 0x0000,
})

local function test_init()
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

test.register_message_test(
  "Basic SET 0x00 should be handled as switch off",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = {mock_device.id, "added"}
    },
    -- {
    --   channel = "capability",
    --   direction = "send",
    --   message = mock_device:generate_test_message("main", capabilities.switch.switch.off())
    -- },
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Basic:Set({value=0x00})) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.off())
    }
  }
)

test.register_message_test(
  "Basic SET 0xFF should be handled as switch on",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = {mock_device.id, "added"}
    },
    -- {
    --   channel = "capability",
    --   direction = "send",
    --   message = mock_device:generate_test_message("main", capabilities.switch.switch.off())
    -- },
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Basic:Set({value=0xFF})) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.on())
    }
  }
)

test.register_coroutine_test(
  "Basic GET should be handled",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.zwave:__queue_receive({mock_device.id,Basic:Set({value=0xFF})})
    test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.switch.switch.on()) )

    test.wait_for_events()
    test.mock_time.advance_time(1)

    test.socket.zwave:__queue_receive({mock_device.id,Basic:Get({})})
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
          mock_device,
          Basic:Report({value=0xFF})
      )
    )
  end
)

test.register_coroutine_test(
  "Basic GET should be handled",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.zwave:__queue_receive({mock_device.id,Basic:Set({value=0x00})})
    test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.switch.switch.off()) )

    test.wait_for_events()
    test.mock_time.advance_time(1)

    test.socket.zwave:__queue_receive({mock_device.id,Basic:Get({})})
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
          mock_device,
          Basic:Report({value=0x00})
      )
    )
  end
)

test.register_message_test(
  "Capability command Off should be handled",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { mock_device.id, { capability = "switch", component = "main", command = "on", args = { } } }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.on())
    }
  }
)

test.register_message_test(
  "Capability command Off should be handled",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { mock_device.id, { capability = "switch", component = "main", command = "off", args = { } } }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.off())
    }
  }
)

test.run_registered_tests()
