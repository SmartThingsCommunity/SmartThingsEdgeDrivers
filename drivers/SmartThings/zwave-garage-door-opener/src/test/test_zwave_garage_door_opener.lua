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
local BarrierOperator = (require "st.zwave.CommandClass.BarrierOperator")({ version = 1 })
local t_utils = require "integration_test.utils"

-- supported comand classes
local garage_door_endpoints = {
  {
    command_classes = {
      {value = zw.BARRIER_OPERATOR},
      {value = zw.NOTIFICATION}
    }
  }
}

local mock_device = test.mock_device.build_test_zwave_device(
  {
    profile = t_utils.get_profile_definition("base-garage-door.yml"),
    zwave_endpoints = garage_door_endpoints
  }
)
local function test_init()
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

test.register_message_test(
    "Barrier operator closed report should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(BarrierOperator:Report({ state = BarrierOperator.state.CLOSED })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.doorControl.door.closed())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.contactSensor.contact.closed())
      }
    }
)

test.register_message_test(
    "Barrier operator closing report should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(BarrierOperator:Report({ state = BarrierOperator.state.CLOSING })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.doorControl.door.closing())
      }
    }
)

test.register_message_test(
    "Barrier operator open report should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(BarrierOperator:Report({ state = BarrierOperator.state.OPEN })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.doorControl.door.open())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.contactSensor.contact.open())
      }
    }
)

test.register_message_test(
    "Barrier operator opening report should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(BarrierOperator:Report({ state = BarrierOperator.state.OPENING })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.doorControl.door.opening())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.contactSensor.contact.open())
      }
    }
)

test.register_message_test(
    "Barrier operator unknown report should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(BarrierOperator:Report({ state = BarrierOperator.state.STOPPED })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.doorControl.door.unknown())
      }
    }
)

test.register_message_test(
  "Open commands should generate correct zwave commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { mock_device.id, { capability = "doorControl", command = "open", args = {} } }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(mock_device, BarrierOperator:Set({target_value = BarrierOperator.target_value.OPEN}))
    }
  },
  {
    test_init = test_init
  }
)

test.register_message_test(
  "Refresh command should prompt correct response",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { mock_device.id, { capability = "refresh", component = "main", command = "refresh", args = {} } }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(mock_device, BarrierOperator:Get({}))
    }
  },
  {
    test_init = test_init,
    inner_block_ordering = "relaxed"
  }
)

test.run_registered_tests()
