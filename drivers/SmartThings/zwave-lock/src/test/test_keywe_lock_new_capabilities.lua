-- Copyright © 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"

local DoorLock = (require "st.zwave.CommandClass.DoorLock")({ version = 1 })
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })
local UserCode = (require "st.zwave.CommandClass.UserCode")({ version = 1 })

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
    profile = t_utils.get_profile_definition("base-lock-tamper.yml"),
    zwave_endpoints = zwave_lock_endpoints,
    zwave_manufacturer_id = KEYWE_MANUFACTURER_ID,
    zwave_product_type = KEYWE_PRODUCT_TYPE,
    zwave_product_id = KEYWE_PRODUCT_ID,
  }
)

-- start with a migrated blank device
local function test_init()
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

local function added()
  test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
  test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCodes.migrated(true,  { visibility = { displayed = false } })))

  test.socket.zwave:__expect_send(
    DoorLock:OperationGet({}):build_test_tx(mock_device.id)
  )
  test.socket.zwave:__expect_send(
    Battery:Get({}):build_test_tx(mock_device.id)
  )
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.tamperAlert.tamper.clear()))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCredentials.supportedCredentials({"pin"}, { visibility = {displayed = false}})))
  test.wait_for_events()
  test.mock_time.advance_time(2)
  test.socket.zwave:__expect_send(
    UserCode:UsersNumberGet({}):build_test_tx(mock_device.id)
  )
  for i = 1, 8 do
    test.socket.zwave:__expect_send(
      UserCode:Get({user_identifier = i}):build_test_tx(mock_device.id)
    )
    test.wait_for_events()
    test.socket.zwave:__queue_receive({mock_device.id, UserCode:Report({
      user_identifier = i,
      user_id_status = UserCode.user_id_status.AVAILABLE
    })})
  end
  test.socket.capability:__expect_send(
    mock_device:generate_test_message(
      "main",
      capabilities.lockUsers.users(
        { },
        { state_change = true, visibility = { displayed = true } }
      )
    )
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message(
      "main",
      capabilities.lockCredentials.credentials(
        { },
        { state_change = true, visibility = { displayed = true } }
      )
    )
  )
  test.wait_for_events()
end

test.register_coroutine_test(
  "Door Lock Operation Reports unlocked should be handled",
  function()
    added()
    test.socket.zwave:__queue_receive({mock_device.id,
      DoorLock:OperationReport({door_lock_mode = 0x00})
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lock.lock.unlocked()))
  end
)

test.register_coroutine_test(
  "Door Lock Operation Reports locked should be handled",
  function()
    added()
    test.socket.zwave:__queue_receive({mock_device.id,
      DoorLock:OperationReport({door_lock_mode = 0xFF})
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lock.lock.locked()))
  end
)

test.register_coroutine_test(
  "Lock notification reporting should be handled",
  function()
    added()
    test.socket.zwave:__queue_receive({ mock_device.id, Notification:Report({notification_type = 6, event = 24}) } )
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lock.lock.unlocked({data={method="manual"}})))
    test.socket.zwave:__queue_receive({ mock_device.id, Notification:Report({notification_type = 6, event = 25}) } )
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lock.lock.locked({data={method="manual"}})))
    -- not a special case for this lock, should be handled as usual
    test.socket.zwave:__queue_receive({ mock_device.id, Notification:Report({notification_type = 6, event = 6, event_parameter = "\x01"}) })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lock.lock.unlocked({data={method="keypad"}})))
  end
)

test.run_registered_tests()
