-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test         = require "integration_test"
local t_utils      = require "integration_test.utils"
local capabilities = require "st.capabilities"
local zw           = require "st.zwave"
local constants    = require "lock_utils.constants"
local zw_test_utils = require "integration_test.zwave_test_utils"

--- @type st.zwave.CommandClass.UserCode
local UserCode     = (require "st.zwave.CommandClass.UserCode")({ version = 1 })
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 2 })
local Association = (require "st.zwave.CommandClass.Association")({ version = 1 })
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
local DoorLock = (require "st.zwave.CommandClass.DoorLock")({ version = 1 })

local PIN_LENGTH_FROM_DEVICE = "pinLengthFromDevice"

local zwave_lock_endpoints = {
  {
    command_classes = {
      { value = zw.BATTERY },
      { value = zw.DOOR_LOCK },
      { value = zw.USER_CODE },
      { value = zw.NOTIFICATION },
    }
  }
}

local mock_device = test.mock_device.build_test_zwave_device({
  profile                = t_utils.get_profile_definition("base-lock.yml"),
  _provisioning_state    = "TYPED",
  zwave_endpoints        = zwave_lock_endpoints,
  zwave_manufacturer_id  = 0x003B,
  zwave_product_type     = 0x0002,
  zwave_product_id       = 0x0469,
})

local function test_init()
  test.disable_startup_messages()
  test.mock_device.add_test_device(mock_device)
  mock_device:set_field(constants.DRIVER_STATE.SLGA_MIGRATED, true, {})
end
test.set_test_init_function(test_init)

local SCHLAGE_LOCK_CODE_LENGTH_PARAM = {number = 16, size = 1}

local function added()
  mock_device:set_field(constants.DRIVER_STATE.SLGA_MIGRATED, nil, {})
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
  test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCodes.migrated(true,  { visibility = { displayed = false } })))

  test.socket.zwave:__expect_send(
    DoorLock:OperationGet({}):build_test_tx(mock_device.id)
  )
  test.socket.zwave:__expect_send(
    Battery:Get({}):build_test_tx(mock_device.id)
  )
  test.socket.zwave:__expect_send(
    UserCode:UsersNumberGet({}):build_test_tx(mock_device.id)
  )
  test.wait_for_events()
  assert(mock_device:get_field(constants.DRIVER_STATE.SLGA_MIGRATED) == true, "Device should be marked as migrated")
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
          capabilities.lockCredentials.credentials({{ userIndex = 1, credentialIndex = 1, credentialType = "pin" }},
          { visibility = { displayed = false } })
        )
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message(
          "main",
          capabilities.lockCredentials.commandResult(
            { commandName = "addCredential", statusCode = "success", credentialIndex = 1, userIndex = 1},
            { state_change = true, visibility = { displayed = false } }
          )
        )
      )
  end,
  { min_api_version = 15 }
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
  end,
  { min_api_version = 15 }
)

test.register_coroutine_test(
  "First configuration report after the default PIN length should not wipe existing credentials",
  function()
    added()
    -- default (4-10) is in place; add a cached credential to confirm it survives the first real report
    mock_device:set_field(PIN_LENGTH_FROM_DEVICE, nil, {})
    local tables = require "lock_utils.tables"
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.credentials({{ userIndex = 1, credentialIndex = 1, credentialType = "pin" }},
        { visibility = { displayed = false } })))
    tables.add_entry(mock_device, "credentials", { userIndex = 1, credentialIndex = 1, credentialType = "pin" })
    test.socket.zwave:__queue_receive({
      mock_device.id,
      Configuration:Report({ parameter_number = SCHLAGE_LOCK_CODE_LENGTH_PARAM.number, configuration_value = 6 })
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.lockCredentials.minPinCodeLen(6)))
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.lockCredentials.maxPinCodeLen(6)))
    test.wait_for_events()
    assert(#(tables.get_state(mock_device, "credentials") or {}) == 1, "credential must not be wiped")
  end,
  { min_api_version = 15 }
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
        { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.credentials({},
        { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.lockCredentials.minPinCodeLen(4))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.lockCredentials.maxPinCodeLen(4))
    )
  end,
  { min_api_version = 15 }
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
        { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.credentials({},
        { visibility = { displayed = false } })
      )
    )
  end,
  { min_api_version = 15 }
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
  end,
  { min_api_version = 15 }
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
  end,
  { min_api_version = 15 }
)

test.register_coroutine_test(
  "Masked occupied USER_CODE_REPORT during code sync advances to the next slot",
  function()
    mock_device:set_field(constants.DRIVER_STATE.BUSY, os.time(), {})
    mock_device:set_field(constants.DRIVER_STATE.COMMAND_IN_PROGRESS, constants.SYNC.CODES_FROM_LOCK, {})
    mock_device:set_field(constants.SYNC.CODE_INDEX, 1, {})

    test.socket.zwave:__queue_receive({
      mock_device.id,
      UserCode:Report({
        user_identifier = 1,
        user_id_status  = UserCode.user_id_status.ENABLED_GRANT_ACCESS,
        user_code       = "**********",
      }),
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(
          { { userIndex = 1, userName = "Guest 1", userType = "guest" } },
          { visibility = { displayed = false } }
        ))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.credentials(
          { { userIndex = 1, credentialIndex = 1, credentialType = "pin", credentialName = "Guest 1" } },
          { visibility = { displayed = false } }
        ))
    )
    test.socket.zwave:__expect_send(
      UserCode:Get({ user_identifier = 2 }):build_test_tx(mock_device.id)
    )
    test.wait_for_events()
  end,
  { min_api_version = 15 }
)

test.run_registered_tests()
