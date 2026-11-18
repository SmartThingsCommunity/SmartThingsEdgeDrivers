-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test         = require "integration_test"
local t_utils      = require "integration_test.utils"
local capabilities = require "st.capabilities"
local zw           = require "st.zwave"
local constants    = require "lock_utils.constants"

--- @type st.zwave.CommandClass.UserCode
local UserCode     = (require "st.zwave.CommandClass.UserCode")({ version = 1 })

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
        capabilities.lockCredentials.credentials(
          { { userIndex = 1, credentialIndex = 1, credentialType = "pin", credentialName = "Guest 1" } },
          { visibility = { displayed = false } }
        ))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(
          { { userIndex = 1, userName = "Guest 1", userType = "guest" } },
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

-- The lock's PIN length is known, so an add is sent at once instead of after a Configuration Get.
local PIN_LENGTH_FROM_DEVICE = "pinLengthFromDevice"

local function expect_set_pin_code(user_identifier, user_code)
  test.socket.zwave:__expect_send(
    UserCode:Set({
      user_identifier = user_identifier,
      user_code       = user_code,
      user_id_status  = UserCode.user_id_status.ENABLED_GRANT_ACCESS,
    }):build_test_tx(mock_device.id)
  )
end

-- How the lock answers a Set it refuses because the PIN is already in use.
local function queue_set_rejected(user_identifier)
  test.socket.zwave:__queue_receive({
    mock_device.id,
    UserCode:Report({
      user_identifier = user_identifier,
      user_id_status  = UserCode.user_id_status.STATUS_NOT_AVAILABLE,
      user_code       = "0000\n\r",
    }),
  })
end

local function expect_command_result(command_name, status_code, extra)
  local result = { commandName = command_name, statusCode = status_code }
  for k, v in pairs(extra or {}) do result[k] = v end
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main",
      capabilities.lockCredentials.commandResult(result, { state_change = true, visibility = { displayed = false } }))
  )
end

local function add_credential(pin)
  test.socket.capability:__queue_receive({
    mock_device.id,
    { capability = capabilities.lockCredentials.ID, command = "addCredential", args = { 0, "guest", "pin", pin } },
  })
end

test.register_coroutine_test(
  "addCredential: a STATUS_NOT_AVAILABLE answer for the new slot is a duplicate PIN, and nothing is added",
  function()
    mock_device:set_field(PIN_LENGTH_FROM_DEVICE, true, { persist = true })
    add_credential("1234")
    expect_set_pin_code(1, "1234")
    test.wait_for_events()

    queue_set_rejected(1)
    expect_command_result("addCredential", "duplicate")
    test.wait_for_events()

    -- the driver is no longer busy, and slot 1 is still free
    add_credential("5678")
    expect_set_pin_code(1, "5678")
    test.wait_for_events()
  end,
  { min_api_version = 15 }
)

test.register_coroutine_test(
  "updateCredential: a STATUS_NOT_AVAILABLE answer is a duplicate PIN, and the credential is unchanged",
  function()
    mock_device:set_field(PIN_LENGTH_FROM_DEVICE, true, { persist = true })
    add_credential("1234")
    expect_set_pin_code(1, "1234")
    test.wait_for_events()

    test.socket.zwave:__queue_receive({
      mock_device.id,
      UserCode:Report({
        user_identifier = 1,
        user_id_status  = UserCode.user_id_status.ENABLED_GRANT_ACCESS,
        user_code       = "1234\n\r",
      }),
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCredentials.credentials(
          { { userIndex = 1, credentialIndex = 1, credentialType = "pin", credentialName = "Guest 1" } },
          { visibility = { displayed = false } }
        ))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(
          { { userIndex = 1, userName = "Guest 1", userType = "guest" } },
          { visibility = { displayed = false } }
        ))
    )
    expect_command_result("addCredential", "success", { userIndex = 1, credentialIndex = 1 })
    test.wait_for_events()

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "updateCredential", args = { 1, 1, "pin", "5678" } },
    })
    expect_set_pin_code(1, "5678")
    test.wait_for_events()

    queue_set_rejected(1)
    expect_command_result("updateCredential", "duplicate")
    test.wait_for_events()
  end,
  { min_api_version = 15 }
)

test.run_registered_tests()
