-- Copyright © 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local zw_test_utils = require "integration_test.zwave_test_utils"
local t_utils = require "integration_test.utils"
local UserCode = (require "st.zwave.CommandClass.UserCode")({version=1})
local DoorLock = (require "st.zwave.CommandClass.DoorLock")({version=1})
local Battery = (require "st.zwave.CommandClass.Battery")({version=1})
local Notification = (require "st.zwave.CommandClass.Notification")({version=3})
local lock_utils = require "new_lock_utils"

local SAMSUNG_MANUFACTURER_ID = 0x022E
local SAMSUNG_PRODUCT_TYPE = 0x0001
local SAMSUNG_PRODUCT_ID = 0x0001

local mock_device = test.mock_device.build_test_zwave_device(
  {
    profile = t_utils.get_profile_definition("base-lock.yml"),
    zwave_manufacturer_id = SAMSUNG_MANUFACTURER_ID,
    zwave_product_type = SAMSUNG_PRODUCT_TYPE,
    zwave_product_id = SAMSUNG_PRODUCT_ID,
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

local function init_code_slot(slot_number, name, device)
  local credentials = device.transient_store[lock_utils.LOCK_CREDENTIALS]
  local users = device.transient_store[lock_utils.LOCK_USERS]
  if credentials == nil then
    credentials = {}
    device.transient_store[lock_utils.LOCK_CREDENTIALS] = credentials
  end
  if users == nil then
    users = {}
    device.transient_store[lock_utils.LOCK_USERS] = users
  end
  table.insert(credentials, { userIndex = slot_number, credentialIndex = slot_number, credentialType = "pin" })
  table.insert(users, { userIndex = slot_number, userName = name, userType = "guest" })
end

test.register_coroutine_test(
  "When the device is added an unlocked event should be sent",
  function()
    added()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.lock.lock.unlocked())
    )
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_coroutine_test(
  "Setting a user code name should be handled",
  function()
    added()
    test.socket.capability:__queue_receive({ mock_device.id, { capability = capabilities.lockCredentials.ID, command = "addCredential", args = { 0, "guest", "pin", "1234"} } })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        UserCode:Set({user_identifier = 1, user_code = "1234", user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS})
      )
    )
    test.wait_for_events()
    test.socket.zwave:__queue_receive({
      mock_device.id,
      Notification:Report({
        notification_type = Notification.notification_type.ACCESS_CONTROL,
        event = Notification.event.access_control.NEW_USER_CODE_ADDED,
        event_parameter = "" }
      )
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        UserCode:Get({user_identifier = 1})
      )
    )
    test.socket.zwave:__queue_receive({
      mock_device.id,
      UserCode:Report({
        user_identifier = 1,
        user_code = "1234",
        user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS
      })
    })
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.users({{ userIndex = 1, userName = "Guest1", userType = "guest" }},
        { state_change = true, visibility = { displayed = true } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.credentials({{ userIndex = 1, credentialIndex = 1, credentialType = "pin" }},
        { state_change = true, visibility = { displayed = true } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.commandResult(
          { commandName = "addCredential", statusCode = "success", credentialIndex = 1, userIndex = 1},
          { state_change = true, visibility = { displayed = true } }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Notification about correctly added code should be handled",
  function()
    added()
    test.socket.capability:__queue_receive({ mock_device.id, { capability = capabilities.lockCredentials.ID, command = "addCredential", args = { 0, "guest", "pin", "1234"} } })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        UserCode:Set({user_identifier = 1, user_code = "1234", user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS})
      )
    )
    test.wait_for_events()
    test.socket.zwave:__queue_receive({ mock_device.id,
      Notification:Report({
        notification_type = Notification.notification_type.ACCESS_CONTROL,
        event = Notification.event.access_control.NEW_USER_CODE_NOT_ADDED_DUE_TO_DUPLICATE_CODE
      })
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.commandResult(
          { commandName = "addCredential", statusCode = "duplicate", credentialIndex = 1, userIndex = 1},
          { state_change = true, visibility = { displayed = true } }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "All user codes should be reported as deleted upon changing Master Code",
  function()
    added()
    init_code_slot(1, "Code 1", mock_device)
    init_code_slot(2, "Code 2", mock_device)
    init_code_slot(3, "Code 3", mock_device)
    test.socket.capability:__queue_receive({
      mock_device.id,
      {
        capability = capabilities.lockUsers.ID,
        command = "updateUser",
        args = {1, "new name", "guest" }
      },
    })
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.commandResult(
          { commandName = "updateUser", statusCode = "success", userIndex = 1 },
          { state_change = true, visibility = { displayed = true } }
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.users({
          { userIndex = 1, userName = "new name", userType = "guest" },
          { userIndex = 2, userName = "Code 2", userType = "guest" },
          { userIndex = 3, userName = "Code 3", userType = "guest" }
        },
        { state_change = true, visibility = { displayed = true } })
      )
    )
    test.wait_for_events()
    test.socket.zwave:__queue_receive({
      mock_device.id,
      Notification:Report({
        notification_type = Notification.notification_type.ACCESS_CONTROL,
        event = Notification.event.access_control.NEW_PROGRAM_CODE_ENTERED_UNIQUE_CODE_FOR_LOCK_CONFIGURATION,
        event_parameter = "" }
      )
    })
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.users({},
        { state_change = true, visibility = { displayed = true } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.credentials({},
        { state_change = true, visibility = { displayed = true } })
      )
    )
  end
)

test.run_registered_tests()
