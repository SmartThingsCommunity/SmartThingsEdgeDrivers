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
--- @type st.zwave.CommandClass.DoorLock
local DoorLock = (require "st.zwave.CommandClass.DoorLock")({ version = 1 })
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
local Time = (require "st.zwave.CommandClass.Time")({ version = 1 })

local DANALOCK_MANUFACTURER_ID = 0x010E
local DANALOCK_PRODUCT_TYPE = 0x0008
local DANALOCK_PRODUCT_ID = 0x0002

local zwave_lock_profile = {
  components = {
    main = {
      capabilities = {
        [capabilities.lock.ID] = { id = capabilities.lock.ID },
        [capabilities.battery.ID] = { id = capabilities.battery.ID }
      },
      id = "main"
    }
  }
}

-- supported comand classes
local zwave_lock_endpoints = {
  {
    command_classes = {
      { value = zw.BATTERY },
      { value = DoorLock }
    }
  }
}

local mock_device = test.mock_device.build_test_zwave_device(
  {
    profile = zwave_lock_profile,
    zwave_endpoints = zwave_lock_endpoints,
    zwave_manufacturer_id = DANALOCK_MANUFACTURER_ID,
    zwave_product_type = DANALOCK_PRODUCT_TYPE,
    zwave_product_id = DANALOCK_PRODUCT_ID
  }
)

local function test_init()
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Door Lock Operation Reports should be handled",
  function()
    test.socket.zwave:__queue_receive({ mock_device.id,
                                        DoorLock:OperationReport({ door_lock_mode = DoorLock.door_lock_mode.DOOR_UNSECURED })
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lock.lock.unlocked()))
  end
)

test.register_message_test(
  "Battery percentage report should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, Battery:Report({ battery_level = 0x32 }) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.battery.battery(50))
    }
  }
)

test.register_message_test(
  "Battery percentage 0xFF report should be handled as 1%",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, Battery:Report({ battery_level = 0xFF }) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.battery.battery(1))
    }
  }
)

test.register_coroutine_test(
  "Sending the lock command should be handled",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(4.2, "oneshot")
    test.socket.capability:__queue_receive({ mock_device.id,
                                             { capability = "lock", component = "main", command = "lock", args = {} }
    })
    test.socket.zwave:__expect_send(DoorLock:OperationSet({ door_lock_mode = DoorLock.door_lock_mode.DOOR_SECURED }):build_test_tx(mock_device.id))
    test.wait_for_events()
    test.mock_time.advance_time(4.2)
    test.socket.zwave:__expect_send(DoorLock:OperationGet({}):build_test_tx(mock_device.id))
  end
)

test.register_coroutine_test(
  "The driver should respond correctly to a time get",
  function ()
    test.socket.zwave:__queue_receive({ mock_device.id, Time:Get({},{
        encap = zw.ENCAP.AUTO,
        src_channel = 0,
        dst_channels = {}
      })
    })
    local time = os.date("*t")
    test.socket.zwave:__expect_send(Time:Report({
      hour_local_time = time.hour,
      minute_local_time = time.min,
      second_local_time = time.sec
    }):build_test_tx(mock_device.id))
  end
)

test.run_registered_tests()
