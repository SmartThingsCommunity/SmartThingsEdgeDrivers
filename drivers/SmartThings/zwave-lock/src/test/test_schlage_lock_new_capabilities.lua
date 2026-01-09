-- Copyright © 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local t_utils = require "integration_test.utils"

local UserCode = (require "st.zwave.CommandClass.UserCode")({ version = 1 })
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 2 })
local Association = (require "st.zwave.CommandClass.Association")({ version = 1 })
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
local DoorLock = (require "st.zwave.CommandClass.DoorLock")({ version = 1 })

local SCHLAGE_MANUFACTURER_ID = 0x003B
local SCHLAGE_PRODUCT_TYPE = 0x0002
local SCHLAGE_PRODUCT_ID = 0x0469

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
    profile = t_utils.get_profile_definition("base-lock.yml"),
    zwave_endpoints = zwave_lock_endpoints,
    zwave_manufacturer_id = SCHLAGE_MANUFACTURER_ID,
    zwave_product_type = SCHLAGE_PRODUCT_TYPE,
    zwave_product_id = SCHLAGE_PRODUCT_ID,
  }
)

local SCHLAGE_LOCK_CODE_LENGTH_PARAM = {number = 16, size = 1}

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

test.register_coroutine_test(
  "Setting a user code should result in the named code changed event firing",
  function()
    added()
    test.timer.__create_and_queue_test_time_advance_timer(4.2, "oneshot")
    test.socket.capability:__queue_receive({ mock_device.id, { capability = capabilities.lockCredentials.ID, command = "addCredential", args = { 0, "guest", "pin", "1234"} } })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Configuration:Get({parameter_number = SCHLAGE_LOCK_CODE_LENGTH_PARAM.number})
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(4.2)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        UserCode:Set({user_identifier = 1, user_code = "1234", user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS})
      )
    )
    test.wait_for_events()
    test.socket.zwave:__queue_receive({mock_device.id, UserCode:Report({user_identifier = 1, user_id_status = UserCode.user_id_status.STATUS_NOT_AVAILABLE, user_code="0000\n\r"}) })
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
  "Configuration report should be handled",
  function()
    added()
    test.socket.zwave:__queue_receive({
      mock_device.id,
      Configuration:Report({
        parameter_number = SCHLAGE_LOCK_CODE_LENGTH_PARAM.number,
        configuration_value = 6
      })
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.lockCredentials.minPinCodeLen(6))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.lockCredentials.maxPinCodeLen(6))
    )
  end
)

test.register_coroutine_test(
  "Configuration report indicating code deletion should be handled",
  function()
    added()
    test.socket.zwave:__queue_receive({
      mock_device.id,
      Configuration:Report({
        parameter_number = SCHLAGE_LOCK_CODE_LENGTH_PARAM.number,
        configuration_value = 6
      })
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.lockCredentials.minPinCodeLen(6))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.lockCredentials.maxPinCodeLen(6))
    )
    test.wait_for_events()
    test.socket.zwave:__queue_receive({
      mock_device.id,
      Configuration:Report({
        parameter_number = SCHLAGE_LOCK_CODE_LENGTH_PARAM.number,
        configuration_value = 4
      })
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
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.lockCredentials.minPinCodeLen(4))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.lockCredentials.maxPinCodeLen(4))
    )
  end
)

test.register_coroutine_test(
  "User code report indicating master code is available should indicate code deletion",
  function()
    added()
    test.socket.zwave:__queue_receive({
      mock_device.id,
      UserCode:Report({
        user_identifier = 0,
        user_id_status = UserCode.user_id_status.AVAILABLE
      })
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

test.register_coroutine_test(
  "Device should send appropriate configuration messages",
  function()
    added()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Configuration:Get({
          parameter_number = SCHLAGE_LOCK_CODE_LENGTH_PARAM.number
        })
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Association:Set({
          grouping_identifier = 2,
          node_ids = {}
        })
      )
    )
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_coroutine_test(
  "Basic Sets should result in an Association remove",
  function()
    added()
    test.socket.zwave:__queue_receive({
      mock_device.id,
      Basic:Set({
        value = 0x00
      })
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.lock.lock.unlocked({}))
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Association:Remove({
          grouping_identifier = 1,
          node_ids = {}
        })
      )
    )
  end
)

test.run_registered_tests()
