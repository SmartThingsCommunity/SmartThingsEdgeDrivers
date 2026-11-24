-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-- Tests for how the Matter lock driver handles the interaction status that comes back for the
-- commands it sends. Every status used here is one the Door Lock cluster spec lists for the command.
--
--  1. SetCredential is answered by SetCredentialResponse, but the spec also has the lock reject it
--     with INVALID_COMMAND as a bare status on the *request* command's path (for example when the
--     UserIndex is already associated with the CredentialIndex). GetUser had the same problem and
--     got a handler for that path; SetCredential has none, so the rejection is dropped, no
--     commandResult is emitted and the lock stays busy.
--  2. SetUser and ClearUser responses are applied even when no matching command is in flight, so a
--     late or duplicate response is attributed to whatever COMMAND_NAME is persisted.
--
-- The expected results are the contract the fixes should meet: the same "invalidCommand" status
-- the SetCredentialResponse path reports, and nothing at all for a response with no matching command.

local test = require "integration_test"
test.set_rpc_version(0)
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local clusters = require "st.matter.clusters"
local cluster_base = require "st.matter.cluster_base"
local im = require "st.matter.interaction_model"
local DoorLock = clusters.DoorLock
local lock_utils = require "lock_utils"

-- DoorLock spec: SetCredential returns INVALID_COMMAND when its fields are invalid.
local INVALID_COMMAND_STATUS = im.InteractionResponse.Status.INVALID_COMMAND
local SUCCESS_STATUS = im.InteractionResponse.Status.SUCCESS

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("lock.yml"),
  manufacturer_info = {
    vendor_id = 0x115f,
    product_id = 0x2802,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        { cluster_id = clusters.BasicInformation.ID, cluster_type = "SERVER" },
      },
      device_types = {
        { device_type_id = 0x0016, device_type_revision = 1 } -- RootNode
      }
    },
    {
      endpoint_id = 1,
      clusters = {
        {
          cluster_id = DoorLock.ID,
          cluster_type = "SERVER",
          cluster_revision = 1,
          feature_map = 0x0591, -- PIN & WDSCH & USR & COTA & YDSCH
        }
      },
      device_types = {
        { device_type_id = 0x000A, device_type_revision = 1 } -- Door Lock
      }
    }
  }
})

local DoorLockFeatureMapAttr = {ID = 0xFFFC, cluster = DoorLock.ID}
local function test_init()
  test.disable_startup_messages()
  -- device_added
  test.mock_device.add_test_device(mock_device)
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main", capabilities.lockAlarm.alarm.clear({state_change = true}))
  )
  -- subscribe request
  local subscribe_request = DoorLock.attributes.LockState:subscribe(mock_device)
  subscribe_request:merge(DoorLock.attributes.OperatingMode:subscribe(mock_device))
  subscribe_request:merge(DoorLock.attributes.NumberOfTotalUsersSupported:subscribe(mock_device))
  subscribe_request:merge(DoorLock.attributes.NumberOfPINUsersSupported:subscribe(mock_device))
  subscribe_request:merge(DoorLock.attributes.MaxPINCodeLength:subscribe(mock_device))
  subscribe_request:merge(DoorLock.attributes.MinPINCodeLength:subscribe(mock_device))
  subscribe_request:merge(DoorLock.attributes.RequirePINforRemoteOperation:subscribe(mock_device))
  subscribe_request:merge(DoorLock.attributes.NumberOfWeekDaySchedulesSupportedPerUser:subscribe(mock_device))
  subscribe_request:merge(DoorLock.attributes.NumberOfYearDaySchedulesSupportedPerUser:subscribe(mock_device))
  subscribe_request:merge(cluster_base.subscribe(mock_device, nil, DoorLockFeatureMapAttr.cluster, DoorLockFeatureMapAttr.ID))
  subscribe_request:merge(DoorLock.events.LockOperation:subscribe(mock_device))
  subscribe_request:merge(DoorLock.events.DoorLockAlarm:subscribe(mock_device))
  subscribe_request:merge(DoorLock.events.LockUserChange:subscribe(mock_device))
  test.socket["matter"]:__expect_send({mock_device.id, subscribe_request})
  -- device_init
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })
  -- do_configure
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main", capabilities.lock.supportedLockCommands({"lock", "unlock"}, {visibility = {displayed = false}}))
  )
  mock_device:expect_metadata_update({ profile = "lock-user-pin-schedule" })
  mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  -- info_changed
  test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({ profile = t_utils.get_profile_definition("lock-user-pin-schedule.yml")}))
  test.socket["matter"]:__expect_send({mock_device.id, subscribe_request})
end

test.set_test_init_function(test_init)

-- SetCredential has its own response command, so it has no status-only builder of its own.
local function set_credential_status(status)
  return DoorLock:build_test_command_response(
    mock_device, 1, DoorLock.ID, DoorLock.server.commands.SetCredential.ID, nil, status
  )
end

local function assert_not_busy()
  assert(not mock_device:get_field(lock_utils.BUSY_STATE), "lock should not be busy after the command finished")
end

----------------------------------------------------------------------------------------------------
-- 1. SetCredential rejected with a status on the request command's path
----------------------------------------------------------------------------------------------------

test.register_coroutine_test(
  "SetCredential rejected with INVALID_COMMAND reports invalidCommand and clears the busy state",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      {
        capability = capabilities.lockCredentials.ID,
        command = "addCredential",
        args = {1, "adminMember", "pin", "654123"}
      },
    })
    test.socket.matter:__expect_send({
      mock_device.id,
      DoorLock.server.commands.SetCredential(
        mock_device, 1,
        DoorLock.types.DataOperationTypeEnum.ADD,
        DoorLock.types.CredentialStruct(
          {credential_type = DoorLock.types.CredentialTypeEnum.PIN, credential_index = 1}
        ),
        "654123",
        1, nil, nil
      ),
    })
    test.wait_for_events()
    -- The lock rejects the command itself, so there is no SetCredentialResponse, only a status
    -- on the SetCredential command path.
    test.socket.matter:__queue_receive({
      mock_device.id,
      set_credential_status(INVALID_COMMAND_STATUS),
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.commandResult(
          {commandName = "addCredential", statusCode = "invalidCommand"},
          {state_change = true, visibility = {displayed = false}}
        )
      )
    )
    test.wait_for_events()
    assert_not_busy()
  end,
  { min_api_version = 14 }
)

test.register_coroutine_test(
  "A SUCCESS status on the SetCredential command path is ignored while waiting for SetCredentialResponse",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      {
        capability = capabilities.lockCredentials.ID,
        command = "addCredential",
        args = {1, "adminMember", "pin", "654123"}
      },
    })
    test.socket.matter:__expect_send({
      mock_device.id,
      DoorLock.server.commands.SetCredential(
        mock_device, 1,
        DoorLock.types.DataOperationTypeEnum.ADD,
        DoorLock.types.CredentialStruct(
          {credential_type = DoorLock.types.CredentialTypeEnum.PIN, credential_index = 1}
        ),
        "654123",
        1, nil, nil
      ),
    })
    test.wait_for_events()
    -- A bare SUCCESS must not be reported as the result; the SetCredentialResponse carries it.
    test.socket.matter:__queue_receive({
      mock_device.id,
      set_credential_status(SUCCESS_STATUS),
    })
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device.id,
      DoorLock.client.commands.SetCredentialResponse:build_test_command_response(
        mock_device, 1,
        DoorLock.types.DlStatus.SUCCESS, 1, 2
      ),
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.credentials(
          {{credentialIndex = 1, credentialType = "pin", userIndex = 1}},
          {visibility = {displayed = false}}
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockCredentials.commandResult(
          {commandName = "addCredential", credentialIndex = 1, statusCode = "success", userIndex = 1},
          {state_change = true, visibility = {displayed = false}}
        )
      )
    )
  end,
  { min_api_version = 14 }
)

----------------------------------------------------------------------------------------------------
-- 2. Responses with no matching command in flight are ignored
----------------------------------------------------------------------------------------------------

test.register_coroutine_test(
  "A SetUser status with no command in flight is ignored",
  function()
    -- Nothing was sent, so there is no COMMAND_NAME and the lock is not busy.
    test.socket.matter:__queue_receive({
      mock_device.id,
      DoorLock.server.commands.SetUser:build_test_command_response(mock_device, 1, SUCCESS_STATUS),
    })
    test.wait_for_events()
  end,
  { min_api_version = 14 }
)

test.register_coroutine_test(
  "A SetUser status that arrives while a different command is in flight is ignored",
  function()
    -- COMMAND_NAME is persisted, so it can still hold the name of an earlier, unrelated command.
    mock_device:set_field(lock_utils.COMMAND_NAME, "deleteCredential", {persist = true})
    test.socket.matter:__queue_receive({
      mock_device.id,
      DoorLock.server.commands.SetUser:build_test_command_response(mock_device, 1, SUCCESS_STATUS),
    })
    test.wait_for_events()
  end,
  { min_api_version = 14 }
)

test.register_coroutine_test(
  "A ClearUser status with no command in flight is ignored",
  function()
    test.socket.matter:__queue_receive({
      mock_device.id,
      DoorLock.server.commands.ClearUser:build_test_command_response(mock_device, 1, SUCCESS_STATUS),
    })
    test.wait_for_events()
  end,
  { min_api_version = 14 }
)

test.run_registered_tests()
