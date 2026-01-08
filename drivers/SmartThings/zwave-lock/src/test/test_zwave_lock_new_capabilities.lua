-- Copyright © 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local zw = require "st.zwave"
--- @type st.zwave.CommandClass.Notification
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })
--- @type st.zwave.CommandClass.UserCode
local UserCode = (require "st.zwave.CommandClass.UserCode")({ version = 1 })
--- @type st.zwave.CommandClass.DoorLock
local DoorLock = (require "st.zwave.CommandClass.DoorLock")({ version = 1 })
--- @type st.zwave.CommandClass.Battery
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
local t_utils = require "integration_test.utils"
local access_control_event = Notification.event.access_control


-- supported comand classes
local zwave_lock_endpoints = {
  {
    command_classes = {
      {value = zw.BATTERY},
      {value = zw.DOOR_LOCK},
      {value = zw.USER_CODE},
      {value = zw.NOTIFICATION}
    }
  }
}
local test_credential_index = 1
local test_credentials = {}
local test_users = {}

local mock_device = test.mock_device.build_test_zwave_device(
    {
      profile = t_utils.get_profile_definition("base-lock-tamper.yml"),
      zwave_endpoints = zwave_lock_endpoints
    }
)

-- if user_index is 0 it creates a new user.
local function add_credential(user_index)
  test.socket.capability:__queue_receive({mock_device.id,
    {
      capability = capabilities.lockCredentials.ID,
      command = "addCredential",
      args = { user_index, "guest", "pin", "123" .. test_credential_index }
    },
  })
  test.socket.zwave:__expect_send(
    UserCode:Set({
      user_identifier = test_credential_index,
      user_code = "123" .. test_credential_index,
      user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS
    }):build_test_tx(mock_device.id)
  )
  test.wait_for_events()

  local payload = "\x70\x01\x00\xFF\x06\x0E\x00\x00"
  payload = payload:sub(1, 1) .. string.char(test_credential_index) .. payload:sub(3)
  test.socket.zwave:__queue_receive({mock_device.id,
    Notification:Report({
      notification_type = Notification.notification_type.ACCESS_CONTROL,
      event = access_control_event.NEW_USER_CODE_ADDED,
      payload = payload
    })
  })
  table.insert(test_users, { userIndex = test_credential_index, userName = "Guest" .. test_credential_index, userType = "guest" })
  test.socket.capability:__expect_send(
    mock_device:generate_test_message(
      "main",
      capabilities.lockUsers.users(test_users,
      { state_change = true, visibility = { displayed = true } })
    )
  )
  table.insert(test_credentials, { userIndex = test_credential_index, credentialIndex = test_credential_index, credentialType = "pin" })
  test.socket.capability:__expect_send(
    mock_device:generate_test_message(
      "main",
      capabilities.lockCredentials.credentials(test_credentials,
      { state_change = true, visibility = { displayed = true } })
    )
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message(
      "main",
      capabilities.lockCredentials.commandResult(
        { commandName = "addCredential", statusCode = "success", credentialIndex = test_credential_index, userIndex = test_credential_index },
        { state_change = true, visibility = { displayed = true } }
      )
    )
  )
  test.wait_for_events()
  test_credential_index = test_credential_index + 1
end

-- start with a migrated blank device
local function test_init()
  test.mock_device.add_test_device(mock_device)
  -- test.socket.capability:__queue_receive({ mock_device.id, { capability = capabilities.lockCodes.ID, command = "migrate", args = {} } })
  -- test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCredentials.minPinCodeLen(4,  { visibility = { displayed = false } })))
  -- test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCredentials.maxPinCodeLen(10,  { visibility = { displayed = false } })))
  -- test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCredentials.pinUsersSupported(8,  { visibility = { displayed = false } })))
  -- test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCredentials.credentials({}, { visibility = { displayed = false } })))
  -- test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCredentials.supportedCredentials({"pin"},  { visibility = { displayed = false } })))
  -- test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockUsers.totalUsersSupported(8, { visibility = { displayed = false } })))
  -- test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockUsers.users({}, { visibility = { displayed = false } })))
  -- test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCodes.migrated(true,  { visibility = { displayed = false } })))

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
  -- test.wait_for_events()
  -- test.mock_time.advance_time(2)
  -- test.socket.zwave:__expect_send(
  --   UserCode:UsersNumberGet({}):build_test_tx(mock_device.id)
  -- )
  -- test.socket.zwave:__expect_send(
  --   UserCode:Get({user_identifier = 1}):build_test_tx(mock_device.id)
  -- )

  -- reset these globals
  test_credential_index = 1
  test_credentials = {}
  test_users = {}
end

test.set_test_init_function(test_init)


test.register_coroutine_test(
  "Add user should succeed",
  function ()
    test.socket.capability:__queue_receive({
      mock_device.id,
      {
        capability = capabilities.lockUsers.ID,
        command = "addUser",
        args = { "TestUser 1", "guest" }
      },
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.users(
          {{userIndex = 1, userType = "guest", userName = "TestUser 1" }},
          { state_change = true, visibility = { displayed = true } }
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.commandResult(
          { commandName = "addUser", statusCode = "success", userIndex = 1 },
          { state_change = true, visibility = { displayed = true } }
        )
      )
    )
    test.socket.capability:__queue_receive({
      mock_device.id,
      {
        capability = capabilities.lockUsers.ID,
        command = "addUser",
        args = { "TestUser 2", "guest" }
      },
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.users(
          {{userIndex = 1, userType = "guest", userName = "TestUser 1" }, {userIndex = 2, userType = "guest", userName = "TestUser 2" }},
          { state_change = true, visibility = { displayed = true } }
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.commandResult(
          { commandName = "addUser", statusCode = "success", userIndex = 2 },
          { state_change = true, visibility = { displayed = true } }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Add credential should succeed",
  function()
    -- these all should succeed
    add_credential(0)
    add_credential(0)
    add_credential(0)
  end
)

test.register_coroutine_test(
  "Add credential for existing user should succeed",
  function ()
    test.socket.capability:__queue_receive({
      mock_device.id,
      {
        capability = capabilities.lockUsers.ID,
        command = "addUser",
        args = { "Guest1", "guest" }
      },
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.users(
          {{userIndex = 1, userType = "guest", userName = "Guest1" }},
          { state_change = true, visibility = { displayed = true } }
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.commandResult(
          { commandName = "addUser", statusCode = "success", userIndex = 1 },
          { state_change = true, visibility = { displayed = true } }
        )
      )
    )
    test.wait_for_events()

    -- add credential with the new users index (1).
    add_credential(1)
  end
)

test.register_coroutine_test(
  "Update user should succeed",
  function ()
    test.socket.capability:__queue_receive({
      mock_device.id,
      {
        capability = capabilities.lockUsers.ID,
        command = "addUser",
        args = { "TestUser 1", "guest" }
      },
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.users(
          {{userIndex = 1, userType = "guest", userName = "TestUser 1" }},
          { state_change = true, visibility = { displayed = true } }
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.commandResult(
          { commandName = "addUser", statusCode = "success", userIndex = 1 },
          { state_change = true, visibility = { displayed = true } }
        )
      )
    )
    test.socket.capability:__queue_receive({
      mock_device.id,
      {
        capability = capabilities.lockUsers.ID,
        command = "addUser",
        args = { "TestUser 2", "guest" }
      },
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.users(
          {{userIndex = 1, userType = "guest", userName = "TestUser 1" }, {userIndex = 2, userType = "guest", userName = "TestUser 2" }},
          { state_change = true,  visibility = { displayed = true } }
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.commandResult(
          { commandName = "addUser", statusCode = "success", userIndex = 2 },
          { state_change = true, visibility = { displayed = true } }
        )
      )
    )
    test.wait_for_events()
    test.socket.capability:__queue_receive({
      mock_device.id,
      {
        capability = capabilities.lockUsers.ID,
        command = "updateUser",
        args = {1, "new name", "guest" }
      },
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.users(
          {{userIndex = 1, userType = "guest", userName = "new name" }, {userIndex = 2, userType = "guest", userName = "TestUser 2" }},
          { state_change = true, visibility = { displayed = true } }
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.commandResult(
          { commandName = "updateUser", statusCode = "success", userIndex = 1 },
          { state_change = true, visibility = { displayed = true } }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Delete user should succeed",
  function()
    -- add credential
    add_credential(0)

    -- delete the user which should also delete the credential
    test.socket.capability:__queue_receive({
      mock_device.id,
      {
        capability = capabilities.lockUsers.ID,
        command = "deleteUser",
        args = { 1 }
      },
    })
    test.socket.zwave:__expect_send(
      UserCode:Set({
        user_identifier = 1,
        user_id_status = UserCode.user_id_status.AVAILABLE
      }):build_test_tx(mock_device.id)
    )
    test.wait_for_events()

    test.socket.zwave:__queue_receive({mock_device.id,
      Notification:Report({
        notification_type = Notification.notification_type.ACCESS_CONTROL,
        event = access_control_event.SINGLE_USER_CODE_DELETED,
        payload = "\x21\x01\x00\xFF\x06\x0D\x00\x00" -- delete payload
      })
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.users(
          {},
          { state_change = true, visibility = { displayed = true } }
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.credentials(
        {},
        { state_change = true, visibility = { displayed = true } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.commandResult(
          { commandName = "deleteUser", statusCode = "success", userIndex = 1 },
          { state_change = true, visibility = { displayed = true } }
        )
      )
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "Update credential should succeed",
  function()
    -- add credential
    add_credential(0)

    -- update the credential
    test.socket.capability:__queue_receive({mock_device.id,
      {
        capability = capabilities.lockCredentials.ID,
        command = "updateCredential",
        args = { 1, 1, "pin", "3456" }
      },
    })
    test.socket.zwave:__expect_send(
      UserCode:Set({
        user_identifier = 1,
        user_code = "3456",
        user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS
      }):build_test_tx(mock_device.id)
    )
    test.wait_for_events()

    test.socket.zwave:__queue_receive({mock_device.id,
      Notification:Report({
        notification_type = Notification.notification_type.ACCESS_CONTROL,
        event = access_control_event.NEW_USER_CODE_ADDED,
        payload = "\x70\x01\x00\xFF\x06\x0E\x00\x00" -- update payload
      })
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.users({{ userIndex = 1, userName = "Guest1", userType = "guest" }}, { state_change = true, visibility = { displayed = true } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.credentials({{ userIndex = 1, credentialIndex = 1, credentialType = "pin" }}, { state_change = true, visibility = { displayed = true } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.commandResult(
          { commandName = "updateCredential", statusCode = "success", credentialIndex = 1, userIndex = 1 },
          { state_change = true, visibility = { displayed = true } }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Delete credential should succeed",
  function()
    -- add the credential
    add_credential(0)

    -- -- delete the credential
    test.socket.capability:__queue_receive({mock_device.id,
      {
        capability = capabilities.lockCredentials.ID,
        command = "deleteCredential",
        args = { 1, "pin" }
      },
    })
    test.socket.zwave:__expect_send(
      UserCode:Set({
        user_identifier = 1,
        user_id_status = UserCode.user_id_status.AVAILABLE
      }):build_test_tx(mock_device.id)
    )
    test.wait_for_events()

    test.socket.zwave:__queue_receive({mock_device.id,
      Notification:Report({
        notification_type = Notification.notification_type.ACCESS_CONTROL,
        event = access_control_event.SINGLE_USER_CODE_DELETED,
        payload = "\x21\x01\x00\xFF\x06\x0D\x00\x00" -- delete payload
      })
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.users(
          {},
          { state_change = true, visibility = { displayed = true } }
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.credentials(
        {},
        { state_change = true, visibility = { displayed = true } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.commandResult(
          { commandName = "deleteCredential", statusCode = "success", credentialIndex = 1, userIndex = 1, },
          { state_change = true, visibility = { displayed = true } }
        )
      )
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "Delete all users should succeed",
  function()
    -- add credential
    add_credential(0)
    -- add second credential
    add_credential(0)

    -- delete all users. This should also delete the two associated credentials
    test.socket.capability:__queue_receive({mock_device.id,
      {
        capability = capabilities.lockUsers.ID,
        command = "deleteAllUsers",
        args = {}
      },
    })

    test.timer.__create_and_queue_test_time_advance_timer(0, "oneshot")
    test.timer.__create_and_queue_test_time_advance_timer(0.5, "oneshot")
    test.mock_time.advance_time(0)
    test.socket.zwave:__expect_send(
      UserCode:Set({
        user_identifier = 1,
        user_id_status = UserCode.user_id_status.AVAILABLE
      }):build_test_tx(mock_device.id)
    )
    test.wait_for_events()
    test.mock_time.advance_time(0.5)
    test.socket.zwave:__expect_send(
      UserCode:Set({
        user_identifier = 2,
        user_id_status = UserCode.user_id_status.AVAILABLE
      }):build_test_tx(mock_device.id)
    )
    test.wait_for_events()

    test.socket.zwave:__queue_receive({mock_device.id,
      Notification:Report({
        notification_type = Notification.notification_type.ACCESS_CONTROL,
        event = access_control_event.SINGLE_USER_CODE_DELETED,
        payload = "\x21\x01\x00\xFF\x06\x0D\x00\x00" -- delete payload
      })
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.users(
          {
            { userIndex = 2, userName = "Guest2", userType = "guest" }
          },
          { state_change = true, visibility = { displayed = true } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.credentials(
        {
          { userIndex = 2, credentialIndex = 2, credentialType = "pin" }
        },
        { state_change = true, visibility = { displayed = true } })
      )
    )


    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.commandResult(
          { commandName = "deleteAllUsers", statusCode = "success"},
          { state_change = true, visibility = { displayed = true } }
        )
      )
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "The lock reporting unlock via code should include the code number",
  function()
    -- add credential
    add_credential(0)
    -- send unlock
    test.socket.zwave:__queue_receive(
      {
        mock_device.id,
        Notification:Report({
          notification_type = Notification.notification_type.ACCESS_CONTROL,
          event = Notification.event.access_control.KEYPAD_UNLOCK_OPERATION,
          event_parameter = "\x01"
        })
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
              capabilities.lock.lock.unlocked({ data = { method = "keypad", userIndex = 1 } })
      )
    )
  end
)

test.register_coroutine_test(
  "When the device is added it should be set up and start reading codes",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.wait_for_events()
    test.mock_time.advance_time(2)
    test.socket.zwave:__expect_send(
      UserCode:UsersNumberGet({}):build_test_tx(mock_device.id)
    )
    test.socket.zwave:__expect_send(
      UserCode:Get({user_identifier = 1}):build_test_tx(mock_device.id)
    )
    test.wait_for_events()
    test.socket.zwave:__queue_receive({mock_device.id, UserCode:Report({
      user_identifier = 1,
      user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS
    })})
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.lockUsers.users(
        { {userIndex = 1, userName = "Guest1", userType = "guest"}},
        { state_change = true, visibility = {displayed = true}}
      ))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.credentials(
        { { userIndex = 1, credentialIndex = 1, credentialType = "pin" } },
        { state_change = true, visibility = { displayed = true } })
      )
    )
    test.socket.zwave:__expect_send(
      UserCode:Get({user_identifier = 2}):build_test_tx(mock_device.id)
    )
  end
)

test.register_coroutine_test(
  "Creating a credential should succeed if the lock responds with a user code report",
  function()
    test.socket.capability:__queue_receive({mock_device.id,
      {
        capability = capabilities.lockCredentials.ID,
        command = "addCredential",
        args = { 0, "guest", "pin", "123" .. test_credential_index }
      },
    })
    test.socket.zwave:__expect_send(
      UserCode:Set({
        user_identifier = test_credential_index,
        user_code = "123" .. test_credential_index,
        user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS
      }):build_test_tx(mock_device.id)
    )
    test.wait_for_events()

    test.socket.zwave:__queue_receive({mock_device.id, UserCode:Report({
      user_identifier = 1,
      user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS
    })})
    table.insert(test_users, { userIndex = test_credential_index, userName = "Guest" .. test_credential_index, userType = "guest" })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.users(test_users,
        { state_change = true, visibility = { displayed = true } })
      )
    )
    table.insert(test_credentials, { userIndex = test_credential_index, credentialIndex = test_credential_index, credentialType = "pin" })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.credentials(test_credentials,
        { state_change = true, visibility = { displayed = true } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.commandResult(
          { commandName = "addCredential", statusCode = "success", credentialIndex = test_credential_index, userIndex = test_credential_index },
          { state_change = true, visibility = { displayed = true } }
        )
      )
    )
    test.wait_for_events()
    test_credential_index = test_credential_index + 1
  end
)

test.run_registered_tests()