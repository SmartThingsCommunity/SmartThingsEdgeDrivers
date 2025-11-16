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
local t_utils = require "integration_test.utils"

local DoorLock = (require "st.zwave.CommandClass.DoorLock")({ version = 1 })
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })

local KEYWE_MANUFACTURER_ID = 0x037B
local KEYWE_PRODUCT_TYPE = 0x0002
local KEYWE_PRODUCT_ID = 0x0001

-- supported comand classes
local zwave_lock_endpoints = {
  {
    command_classes = {
      {value = DoorLock}
    }
  }
}

local mock_device = test.mock_device.build_test_zwave_device(
  {
    profile = t_utils.get_profile_definition("base-lock.yml"),
    zwave_endpoints = zwave_lock_endpoints,
    zwave_manufacturer_id = KEYWE_MANUFACTURER_ID,
    zwave_product_type = KEYWE_PRODUCT_TYPE,
    zwave_product_id = KEYWE_PRODUCT_ID
  }
)

local function test_init()
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Door Lock Operation Reports unlocked should be handled",
  function()
    test.socket.zwave:__queue_receive({mock_device.id,
      DoorLock:OperationReport({door_lock_mode = 0x00})
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lock.lock.unlocked()))
  end
)

test.register_coroutine_test(
  "Door Lock Operation Reports locked should be handled",
  function()
    test.socket.zwave:__queue_receive({mock_device.id,
      DoorLock:OperationReport({door_lock_mode = 0xFF})
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lock.lock.locked()))
  end
)

test.register_message_test(
  "Lock notification reporting should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        Notification:Report({notification_type = 6, event = 24})
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.lock.lock.unlocked({data={method="manual"}}))
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        Notification:Report({notification_type = 6, event = 25})
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.lock.lock.locked({data={method="manual"}}))
    }
  }
)

test.run_registered_tests()
