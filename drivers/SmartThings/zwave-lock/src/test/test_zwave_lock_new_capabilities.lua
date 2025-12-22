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
local json = require "dkjson"
--- @type st.zwave.constants
local constants = require "st.zwave.constants"
--- @type st.zwave.CommandClass.DoorLock
local DoorLock = (require "st.zwave.CommandClass.DoorLock")({ version = 1 })
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
--- @type st.zwave.CommandClass.Notification
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })
--- @type st.zwave.CommandClass.UserCode
local UserCode = (require "st.zwave.CommandClass.UserCode")({ version = 1 })
--- @type st.zwave.CommandClass.Alarm
local Alarm = (require "st.zwave.CommandClass.Alarm")({ version = 1 })
local t_utils = require "integration_test.utils"
local zw_test_utils = require "integration_test.zwave_test_utils"

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

local mock_device = test.mock_device.build_test_zwave_device(
    {
      profile = t_utils.get_profile_definition("base-lock-tamper.yml"),
      zwave_endpoints = zwave_lock_endpoints
    }
)

-- start with a migrated blank device
local function test_init()
  test.mock_device.add_test_device(mock_device)
  test.socket.capability:__queue_receive({ mock_device.id, { capability = capabilities.lockCodes.ID, command = "migrate", args = {} } })
  test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCredentials.minPinCodeLen(4,  { visibility = { displayed = false } })))
  test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCredentials.maxPinCodeLen(10,  { visibility = { displayed = false } })))
  test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCredentials.pinUsersSupported(8,  { visibility = { displayed = false } })))
  test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCredentials.credentials({}, { visibility = { displayed = false } })))
  test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCredentials.supportedCredentials({"pin"},  { visibility = { displayed = false } })))
  test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockUsers.totalUsersSupported(8, { visibility = { displayed = false } })))
  test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockUsers.users({}, { visibility = { displayed = false } })))
  test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCodes.migrated(true,  { visibility = { displayed = false } })))
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
          { visibility = { displayed = false } }
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.commandResult(
          { commandName = "addUser", statusCode = "success", userIndex = 1 },
          { state_change = true, visibility = { displayed = false } }
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
          { visibility = { displayed = false } }
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.commandResult(
          { commandName = "addUser", statusCode = "success", userIndex = 2 },
          { state_change = true, visibility = { displayed = false } }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Add credential should succeed",
  function()
    test.socket.capability:__queue_receive({mock_device.id,
      {
        capability = capabilities.lockCredentials.ID,
        command = "addCredential",
        args = { 1, "guest", "pin", "1234" }
      },
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.users(
          {{userIndex = 1, userType = "guest", userName = "Code 1" }},
          { visibility = { displayed = false } }
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.commandResult(
          { commandName = "addUser", statusCode = "success", userIndex = 1 },
          { state_change = true, visibility = { displayed = false } }
        )
      )
    )
    test.socket.zwave:__expect_send(
      UserCode:Set({
        user_identifier = 1,
        user_code = "1234",
        user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS
      }):build_test_tx(mock_device.id)
    )
    test.wait_for_events()
    test.socket.zwave:__queue_receive({mock_device.id,
      UserCode:Report({
        user_identifier = 1,
        user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS
      })
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.credentials({{ userIndex = 1, credentialIndex = 1, credentialType = "pin" }}, { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.commandResult(
          { commandName = "addCredential", statusCode = "success", credentialIndex = 1 },
          { state_change = true, visibility = { displayed = false } }
        )
      )
    )
    test.wait_for_events()
    test.socket.capability:__queue_receive({mock_device.id,
      {
        capability = capabilities.lockCredentials.ID,
        command = "addCredential",
        args = { 2, "guest", "pin", "3456" }
      },
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.users(
          {
            {userIndex = 1, userType = "guest", userName = "Code 1" },
            {userIndex = 2, userType = "guest", userName = "Code 2" }},
          { visibility = { displayed = false } }
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.commandResult(
          { commandName = "addUser", statusCode = "success", userIndex = 2 },
          { state_change = true, visibility = { displayed = false } }
        )
      )
    )
    test.socket.zwave:__expect_send(
      UserCode:Set({
        user_identifier = 2,
        user_code = "3456",
        user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS
      }):build_test_tx(mock_device.id)
    )
    test.wait_for_events()
    test.socket.zwave:__queue_receive({mock_device.id,
      UserCode:Report({
        user_identifier = 2,
        user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS
      })
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.credentials({
          { userIndex = 1, credentialIndex = 1, credentialType = "pin" },
          { userIndex = 2, credentialIndex = 2, credentialType = "pin" }
        }, { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.commandResult(
          { commandName = "addCredential", statusCode = "success", credentialIndex = 2 },
          { state_change = true, visibility = { displayed = false } }
        )
      )
    )
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
        args = { "TestUser 1", "guest" }
      },
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.users(
          {{userIndex = 1, userType = "guest", userName = "TestUser 1" }},
          { visibility = { displayed = false } }
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.commandResult(
          { commandName = "addUser", statusCode = "success", userIndex = 1 },
          { state_change = true, visibility = { displayed = false } }
        )
      )
    )
    test.wait_for_events()
    test.socket.capability:__queue_receive({mock_device.id,
      {
        capability = capabilities.lockCredentials.ID,
        command = "addCredential",
        args = { 1, "guest", "pin", "1234" }
      },
    })
    test.socket.zwave:__expect_send(
      UserCode:Set({
        user_identifier = 1,
        user_code = "1234",
        user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS
      }):build_test_tx(mock_device.id)
    )
    test.wait_for_events()
    test.socket.zwave:__queue_receive({mock_device.id,
      UserCode:Report({
        user_identifier = 1,
        user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS
      })
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.credentials({{ userIndex = 1, credentialIndex = 1, credentialType = "pin" }}, { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.commandResult(
          { commandName = "addCredential", statusCode = "success", credentialIndex = 1 },
          { state_change = true, visibility = { displayed = false } }
        )
      )
    )
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
          { visibility = { displayed = false } }
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.commandResult(
          { commandName = "addUser", statusCode = "success", userIndex = 1 },
          { state_change = true, visibility = { displayed = false } }
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
          { visibility = { displayed = false } }
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.commandResult(
          { commandName = "addUser", statusCode = "success", userIndex = 2 },
          { state_change = true, visibility = { displayed = false } }
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
          { visibility = { displayed = false } }
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.commandResult(
          { commandName = "updateUser", statusCode = "success", userIndex = 1 },
          { state_change = true, visibility = { displayed = false } }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Delete user should succeed",
  function()
    test.socket.capability:__queue_receive({mock_device.id,
      {
        capability = capabilities.lockCredentials.ID,
        command = "addCredential",
        args = { 1, "guest", "pin", "1234" }
      },
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.users(
          {{userIndex = 1, userType = "guest", userName = "Code 1" }},
          { visibility = { displayed = false } }
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.commandResult(
          { commandName = "addUser", statusCode = "success", userIndex = 1 },
          { state_change = true, visibility = { displayed = false } }
        )
      )
    )
    test.socket.zwave:__expect_send(
      UserCode:Set({
        user_identifier = 1,
        user_code = "1234",
        user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS
      }):build_test_tx(mock_device.id)
    )
    test.wait_for_events()
    test.socket.zwave:__queue_receive({mock_device.id,
      UserCode:Report({
        user_identifier = 1,
        user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS
      })
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.credentials({{ userIndex = 1, credentialIndex = 1, credentialType = "pin" }}, { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.commandResult(
          { commandName = "addCredential", statusCode = "success", credentialIndex = 1 },
          { state_change = true, visibility = { displayed = false } }
        )
      )
    )
    test.wait_for_events()
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
    test.timer.__create_and_queue_test_time_advance_timer(4.2, "oneshot")
    test.wait_for_events()

    test.mock_time.advance_time(4.2)
    test.socket.zwave:__expect_send(UserCode:Get( {user_identifier = 1}):build_test_tx(mock_device.id))
    test.socket.zwave:__queue_receive({mock_device.id,
      UserCode:Report({
        user_identifier = 1,
        user_id_status = UserCode.user_id_status.AVAILABLE
      })
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.credentials({}, { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.commandResult(
          { commandName = "deleteCredential", statusCode = "success", credentialIndex = 1 },
          { state_change = true, visibility = { displayed = false } }
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.users(
          {},
          { visibility = { displayed = false } }
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.commandResult(
          { commandName = "deleteUser", statusCode = "success", userIndex = 1 },
          { state_change = true, visibility = { displayed = false } }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Update credential should succeed",
  function()
    test.socket.capability:__queue_receive({mock_device.id,
      {
        capability = capabilities.lockCredentials.ID,
        command = "addCredential",
        args = { 1, "guest", "pin", "1234" }
      },
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.users(
          {{userIndex = 1, userType = "guest", userName = "Code 1" }},
          { visibility = { displayed = false } }
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.commandResult(
          { commandName = "addUser", statusCode = "success", userIndex = 1 },
          { state_change = true, visibility = { displayed = false } }
        )
      )
    )
    test.socket.zwave:__expect_send(
      UserCode:Set({
        user_identifier = 1,
        user_code = "1234",
        user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS
      }):build_test_tx(mock_device.id)
    )
    test.wait_for_events()
    test.socket.zwave:__queue_receive({mock_device.id,
      UserCode:Report({
        user_identifier = 1,
        user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS
      })
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.credentials({{ userIndex = 1, credentialIndex = 1, credentialType = "pin" }}, { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.commandResult(
          { commandName = "addCredential", statusCode = "success", credentialIndex = 1 },
          { state_change = true, visibility = { displayed = false } }
        )
      )
    )
    test.wait_for_events()
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
      UserCode:Report({
        user_identifier = 1,
        user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS
      })
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.credentials({{ userIndex = 1, credentialIndex = 1, credentialType = "pin" }}, { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.commandResult(
          { commandName = "updateCredential", statusCode = "success", credentialIndex = 1 },
          { state_change = true, visibility = { displayed = false } }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Delete credential should succeed",
  function()
    test.socket.capability:__queue_receive({mock_device.id,
      {
        capability = capabilities.lockCredentials.ID,
        command = "addCredential",
        args = { 1, "guest", "pin", "1234" }
      },
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.users(
          {{userIndex = 1, userType = "guest", userName = "Code 1" }},
          { visibility = { displayed = false } }
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.commandResult(
          { commandName = "addUser", statusCode = "success", userIndex = 1 },
          { state_change = true, visibility = { displayed = false } }
        )
      )
    )
    test.socket.zwave:__expect_send(
      UserCode:Set({
        user_identifier = 1,
        user_code = "1234",
        user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS
      }):build_test_tx(mock_device.id)
    )
    test.wait_for_events()
    test.socket.zwave:__queue_receive({mock_device.id,
      UserCode:Report({
        user_identifier = 1,
        user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS
      })
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.credentials({{ userIndex = 1, credentialIndex = 1, credentialType = "pin" }}, { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.commandResult(
          { commandName = "addCredential", statusCode = "success", credentialIndex = 1 },
          { state_change = true, visibility = { displayed = false } }
        )
      )
    )
    test.wait_for_events()
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
      UserCode:Report({
        user_identifier = 1,
        user_id_status = UserCode.user_id_status.AVAILABLE
      })
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.credentials({}, { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.commandResult(
          { commandName = "deleteCredential", statusCode = "success", credentialIndex = 1 },
          { state_change = true, visibility = { displayed = false } }
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.users(
          {},
          { visibility = { displayed = false } }
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.commandResult(
          { commandName = "deleteUser", statusCode = "success", userIndex = 1 },
          { state_change = true, visibility = { displayed = false } }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Delete all users should succeed",
  function()
    test.socket.capability:__queue_receive({mock_device.id,
      {
        capability = capabilities.lockCredentials.ID,
        command = "addCredential",
        args = { 1, "guest", "pin", "1234" }
      },
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.users(
          {{userIndex = 1, userType = "guest", userName = "Code 1" }},
          { visibility = { displayed = false } }
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.commandResult(
          { commandName = "addUser", statusCode = "success", userIndex = 1 },
          { state_change = true, visibility = { displayed = false } }
        )
      )
    )
    test.socket.zwave:__expect_send(
      UserCode:Set({
        user_identifier = 1,
        user_code = "1234",
        user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS
      }):build_test_tx(mock_device.id)
    )
    test.wait_for_events()
    test.socket.zwave:__queue_receive({mock_device.id,
      UserCode:Report({
        user_identifier = 1,
        user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS
      })
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.credentials({{ userIndex = 1, credentialIndex = 1, credentialType = "pin" }}, { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.commandResult(
          { commandName = "addCredential", statusCode = "success", credentialIndex = 1 },
          { state_change = true, visibility = { displayed = false } }
        )
      )
    )
    test.wait_for_events()
    test.socket.capability:__queue_receive({mock_device.id,
      {
        capability = capabilities.lockCredentials.ID,
        command = "addCredential",
        args = { 2, "guest", "pin", "3456" }
      },
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.users(
          {
            {userIndex = 1, userType = "guest", userName = "Code 1" },
            {userIndex = 2, userType = "guest", userName = "Code 2" }},
          { visibility = { displayed = false } }
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.commandResult(
          { commandName = "addUser", statusCode = "success", userIndex = 2 },
          { state_change = true, visibility = { displayed = false } }
        )
      )
    )
    test.socket.zwave:__expect_send(
      UserCode:Set({
        user_identifier = 2,
        user_code = "3456",
        user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS
      }):build_test_tx(mock_device.id)
    )
    test.wait_for_events()
    test.socket.zwave:__queue_receive({mock_device.id,
      UserCode:Report({
        user_identifier = 2,
        user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS
      })
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.credentials({
          { userIndex = 1, credentialIndex = 1, credentialType = "pin" },
          { userIndex = 2, credentialIndex = 2, credentialType = "pin" }
        }, { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.commandResult(
          { commandName = "addCredential", statusCode = "success", credentialIndex = 2 },
          { state_change = true, visibility = { displayed = false } }
        )
      )
    )
    test.wait_for_events()
    test.socket.capability:__queue_receive({mock_device.id,
      {
        capability = capabilities.lockUsers.ID,
        command = "deleteAllUsers",
        args = {}
      },
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.users({}, { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.commandResult(
          { commandName = "deleteAllUsers", statusCode = "success" },
          { state_change = true, visibility = { displayed = false } }
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.credentials({}, { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.commandResult(
          { commandName = "deleteAllCredentials", statusCode = "success" },
          { state_change = true, visibility = { displayed = false } }
        )
      )
    )
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
  end
)

test.register_coroutine_test(
  "The lock reporting unlock via code should include the code number",
  function()
    test.socket.capability:__queue_receive({mock_device.id,
      {
        capability = capabilities.lockCredentials.ID,
        command = "addCredential",
        args = { 1, "guest", "pin", "1234" }
      },
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.users(
          {{userIndex = 1, userType = "guest", userName = "Code 1" }},
          { visibility = { displayed = false } }
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.commandResult(
          { commandName = "addUser", statusCode = "success", userIndex = 1 },
          { state_change = true, visibility = { displayed = false } }
        )
      )
    )
    test.socket.zwave:__expect_send(
      UserCode:Set({
        user_identifier = 1,
        user_code = "1234",
        user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS
      }):build_test_tx(mock_device.id)
    )
    test.wait_for_events()
    test.socket.zwave:__queue_receive({mock_device.id,
      UserCode:Report({
        user_identifier = 1,
        user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS
      })
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.credentials({{ userIndex = 1, credentialIndex = 1, credentialType = "pin" }}, { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.commandResult(
          { commandName = "addCredential", statusCode = "success", credentialIndex = 1 },
          { state_change = true, visibility = { displayed = false } }
        )
      )
    )
    test.wait_for_events()
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

test.run_registered_tests()