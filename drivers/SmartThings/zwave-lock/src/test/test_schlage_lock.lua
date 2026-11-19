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

-- How the lock confirms a Set: the slot is reported occupied, with the code masked unless `user_code` is given.
local function queue_occupied_report(user_identifier, user_code)
  test.socket.zwave:__queue_receive({
    mock_device.id,
    UserCode:Report({
      user_identifier = user_identifier,
      user_id_status  = UserCode.user_id_status.ENABLED_GRANT_ACCESS,
      user_code       = user_code,
    }),
  })
end

local function queue_masked_occupied_report(user_identifier)
  queue_occupied_report(user_identifier, "**********")
end

local function update_credential(pin)
  test.socket.capability:__queue_receive({
    mock_device.id,
    { capability = capabilities.lockCredentials.ID, command = "updateCredential", args = { 1, 1, "pin", pin } },
  })
end

local function expect_guest_1_added()
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
  "addCredential for an existing user: a STATUS_NOT_AVAILABLE answer keeps the user and adds no credential",
  function()
    mock_device:set_field(PIN_LENGTH_FROM_DEVICE, true, { persist = true })
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockUsers.ID, command = "addUser", args = { "Alice", "guest" } },
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.users(
          { { userIndex = 1, userName = "Alice", userType = "guest" } },
          { visibility = { displayed = false } }
        ))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockUsers.commandResult(
          { commandName = "addUser", statusCode = "success", userIndex = 1 },
          { state_change = true, visibility = { displayed = false } }
        ))
    )
    test.wait_for_events()

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "addCredential", args = { 1, "guest", "pin", "1234" } },
    })
    expect_set_pin_code(1, "1234")
    test.wait_for_events()

    queue_set_rejected(1)
    expect_command_result("addCredential", "duplicate")
    test.wait_for_events()

    -- user 1 still exists and has no credential, so another PIN can be added for it
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = capabilities.lockCredentials.ID, command = "addCredential", args = { 1, "guest", "pin", "5678" } },
    })
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

    queue_occupied_report(1, "1234\n\r")
    expect_guest_1_added()
    test.wait_for_events()

    update_credential("5678")
    expect_set_pin_code(1, "5678")
    test.wait_for_events()

    queue_set_rejected(1)
    expect_command_result("updateCredential", "duplicate")
    test.wait_for_events()

    -- the driver is no longer busy, so the update can be retried with another PIN
    update_credential("2468")
    expect_set_pin_code(1, "2468")
    test.wait_for_events()
  end,
  { min_api_version = 15 }
)

test.register_coroutine_test(
  "addCredential: a masked occupied report for the new slot confirms the add",
  function()
    mock_device:set_field(PIN_LENGTH_FROM_DEVICE, true, { persist = true })
    add_credential("1234")
    expect_set_pin_code(1, "1234")
    test.wait_for_events()

    queue_masked_occupied_report(1)
    expect_guest_1_added()
    test.wait_for_events()

    -- slot 1 is now recorded, so the next add goes to slot 2 instead of overwriting it
    add_credential("5678")
    expect_set_pin_code(2, "5678")
    test.wait_for_events()
  end,
  { min_api_version = 15 }
)

test.register_coroutine_test(
  "addCredential: a masked occupied report for another slot does not confirm the add",
  function()
    mock_device:set_field(PIN_LENGTH_FROM_DEVICE, true, { persist = true })
    add_credential("1234")
    expect_set_pin_code(1, "1234")
    test.wait_for_events()

    queue_masked_occupied_report(7)
    test.wait_for_events()
  end,
  { min_api_version = 15 }
)

test.register_coroutine_test(
  "updateCredential: a masked occupied report for the slot confirms the update",
  function()
    mock_device:set_field(PIN_LENGTH_FROM_DEVICE, true, { persist = true })
    add_credential("1234")
    expect_set_pin_code(1, "1234")
    test.wait_for_events()
    queue_masked_occupied_report(1)
    expect_guest_1_added()
    test.wait_for_events()

    update_credential("5678")
    expect_set_pin_code(1, "5678")
    test.wait_for_events()

    queue_masked_occupied_report(1)
    expect_command_result("updateCredential", "success", { userIndex = 1, credentialIndex = 1 })
    test.wait_for_events()
  end,
  { min_api_version = 15 }
)

-- A blank code is not consumed as manufacturer-specific, so it confirms the add with or without the masked-code check.
test.register_coroutine_test(
  "addCredential: an occupied report with a blank code for the new slot confirms the add",
  function()
    mock_device:set_field(PIN_LENGTH_FROM_DEVICE, true, { persist = true })
    add_credential("1234")
    expect_set_pin_code(1, "1234")
    test.wait_for_events()

    queue_occupied_report(1, "")
    expect_guest_1_added()
    test.wait_for_events()
  end,
  { min_api_version = 15 }
)

test.register_coroutine_test(
  "updateCredential: a masked occupied report for another slot does not confirm the update",
  function()
    mock_device:set_field(PIN_LENGTH_FROM_DEVICE, true, { persist = true })
    add_credential("1234")
    expect_set_pin_code(1, "1234")
    test.wait_for_events()
    queue_masked_occupied_report(1)
    expect_guest_1_added()
    test.wait_for_events()

    update_credential("5678")
    expect_set_pin_code(1, "5678")
    test.wait_for_events()

    -- not the slot being updated, so nothing is emitted
    queue_masked_occupied_report(7)
    test.wait_for_events()

    -- the update is still waiting, and the report for its own slot confirms it
    queue_masked_occupied_report(1)
    expect_command_result("updateCredential", "success", { userIndex = 1, credentialIndex = 1 })
    test.wait_for_events()
  end,
  { min_api_version = 15 }
)

test.run_registered_tests()
