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
-- Mock out globals
local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local json = require "st.json"
local clusters = require "st.matter.clusters"
local DoorLock = clusters.DoorLock
local types = DoorLock.types
local data_types = require "st.matter.data_types"

local mock_device_record = {
  profile = t_utils.get_profile_definition("base-lock.yml"),
  manufacturer_info = {vendor_id = 0xcccc, product_id = 0x1},
  endpoints = {
    {
      endpoint_id = 1,
      clusters = {
        {
          cluster_id = DoorLock.ID,
          cluster_type = "SERVER",
          feature_map = 0x0181, -- PIN & USR & COTA
        },
        {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER"},
      },
    },
  },
}
local mock_device = test.mock_device.build_test_matter_device(mock_device_record)

local function test_init()
  local subscribe_request = DoorLock.attributes.LockState:subscribe(mock_device)
  subscribe_request:merge(clusters.PowerSource.attributes.BatPercentRemaining:subscribe(mock_device))
  subscribe_request:merge(DoorLock.events.LockUserChange:subscribe(mock_device))
  test.socket["matter"]:__expect_send({mock_device.id, subscribe_request})
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

local expect_reload_all_codes_messages = function(dev)
  local credential = types.DlCredential({credential_type = types.DlCredentialType.PIN, credential_index = 1})
  test.socket.capability:__expect_send(
    dev:generate_test_message(
      "main", capabilities.lockCodes.scanCodes("Scanning")
    )
  )
  test.socket.matter:__expect_send(
    {dev.id, DoorLock.server.commands.GetCredentialStatus(dev, 1, credential)}
  )
  test.wait_for_events()
end

local test_credential_data = "12345678"

local function expect_kick_off_cota_process(device)
  test.socket.device_lifecycle:__queue_receive({ device.id, "added" })
  test.socket.capability:__expect_send(
    device:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
  )
  local req = DoorLock.attributes.MaxPINCodeLength:read(device, 1)
  req:merge(DoorLock.attributes.MinPINCodeLength:read(device, 1))
  req:merge(DoorLock.attributes.NumberOfPINUsersSupported:read(device, 1))
  req:merge(DoorLock.attributes.RequirePINforRemoteOperation:read(device, 1))
  test.socket.matter:__expect_send({device.id, req})
  expect_reload_all_codes_messages(device)
  test.wait_for_events()

  test.socket.capability:__expect_send(device:generate_test_message("main", capabilities.lockCodes.maxCodes(16, {visibility = {displayed = false}})))
  test.socket.matter:__queue_receive({
    device.id,
    DoorLock.attributes.NumberOfPINUsersSupported:build_test_report_data(device, 1, 16),
  })

  -- The creation of advance timers, advancing time, and waiting for events
  -- is done to ensure a correct order of operations and allow for all the
  -- `call_with_delay(0, ...)` calls to execute at the correct time.
  test.wait_for_events()
  test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")

  test.socket.matter:__queue_receive(
    {
      device.id,
      DoorLock.attributes.RequirePINforRemoteOperation:build_test_report_data(
        device, 1, true
      ),
    }
  )
  test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
  test.mock_time.advance_time(1) --trigger remote pin handling
  test.wait_for_events()
  device:set_field("cotaCred", test_credential_data, {persist = true}) --overwrite random cred for test expectation
  test.timer.__create_and_queue_test_time_advance_timer(3, "oneshot")

  test.socket.matter:__expect_send(
    {
      device.id,
      DoorLock.server.commands.SetCredential(
        device, 1, -- endpoint
        DoorLock.types.DlDataOperationType.ADD, -- operation_type
        DoorLock.types.DlCredential(
          {credential_type = DoorLock.types.DlCredentialType.PIN, credential_index = 1}
        ), -- credential
        test_credential_data, -- credential_data
        nil, -- user_index
        DoorLock.types.DlUserStatus.OCCUPIED_ENABLED, -- user_status
        DoorLock.types.DlUserType.REMOTE_ONLY_USER -- user_type
      ),
    }
  )
  test.mock_time.advance_time(1) --trigger set_cota_credential
  test.wait_for_events()
end

test.register_coroutine_test(
  "Added should kick off cota cred process", function()
    test.socket.matter:__set_channel_ordering("relaxed")
    expect_kick_off_cota_process(mock_device)
  end
)

test.register_coroutine_test(
  "SetCredential for OCCUPIED credential index requests next_credential_index", function()
    test.socket.matter:__set_channel_ordering("relaxed")
    expect_kick_off_cota_process(mock_device)

    local next_credential_index = 6
    test.socket.matter:__queue_receive({
      mock_device.id,
      DoorLock.client.commands.SetCredentialResponse:build_test_command_response(
        mock_device, 1,
        DoorLock.types.DlStatus.OCCUPIED,
        1, --user_index
        next_credential_index
      ),
    })
    test.socket.matter:__expect_send({
      mock_device.id,
      DoorLock.server.commands.SetCredential(
        mock_device, 1, -- endpoint
        DoorLock.types.DlDataOperationType.ADD, -- operation_type
        DoorLock.types.DlCredential(
          {credential_type = DoorLock.types.DlCredentialType.PIN, credential_index = next_credential_index}
        ), -- credential
        test_credential_data, -- credential_data
        nil, -- user_index
        DoorLock.types.DlUserStatus.OCCUPIED_ENABLED, -- user_status
        DoorLock.types.DlUserType.REMOTE_ONLY_USER -- user_type
      )
    })
  end
)

test.register_coroutine_test(
  "SetCredential for OCCUPIED credential index no space on device", function()
    test.socket.matter:__set_channel_ordering("relaxed")
    expect_kick_off_cota_process(mock_device)

    local next_credential_index = data_types.Null()
    test.socket.matter:__queue_receive({
      mock_device.id,
      DoorLock.client.commands.SetCredentialResponse:build_test_command_response(
        mock_device, 1,
        DoorLock.types.DlStatus.OCCUPIED,
        1,  -- user_index
        nil -- next_redential_index
      ),
    })
    mock_device:expect_metadata_update({
      profile = "nonfunctional-lock",
      provisioning_state = "NONFUNCTIONAL"
    })
  end
)

test.register_coroutine_test(
  "User creates space for COTA credential on a nonfunctional lock", function()
    test.socket.matter:__set_channel_ordering("relaxed")
    expect_kick_off_cota_process(mock_device)

    local next_credential_index = data_types.Null()
    test.socket.matter:__queue_receive({
      mock_device.id,
      DoorLock.client.commands.SetCredentialResponse:build_test_command_response(
        mock_device, 1,
        DoorLock.types.DlStatus.OCCUPIED,
        1,  -- user_index
        nil -- next_redential_index
      ),
    })
    mock_device:expect_metadata_update({
      profile = "nonfunctional-lock",
      provisioning_state = "NONFUNCTIONAL"
    })
    test.wait_for_events()

    test.socket.capability:__queue_receive(
      {mock_device.id, {capability = capabilities.lockCodes.ID, command = "deleteCode", args = {1}}}
    )
    test.socket.matter:__expect_send({
      mock_device.id,
      DoorLock.server.commands.ClearCredential(
        mock_device,
        1,
        {credential_type = types.DlCredentialType.PIN, credential_index = 1}
      )
    })
    test.wait_for_events()

    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.server.commands.ClearCredential:build_test_command_response(mock_device, 1),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.lockCodes
          .codeChanged("1 deleted", {data = {codeName = "Code 1"}, state_change = true})
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
          capabilities.lockCodes.lockCodes(json.encode({}), {visibility = {displayed = false}})
      )
    )
    test.socket.matter:__expect_send({
      mock_device.id,
      DoorLock.server.commands.SetCredential(
        mock_device, 1, -- endpoint
        DoorLock.types.DlDataOperationType.ADD, -- operation_type
        DoorLock.types.DlCredential(
          {credential_type = DoorLock.types.DlCredentialType.PIN, credential_index = 1}
        ), -- credential
        test_credential_data, -- credential_data
        nil, -- user_index
        DoorLock.types.DlUserStatus.OCCUPIED_ENABLED, -- user_status
        DoorLock.types.DlUserType.REMOTE_ONLY_USER -- user_type
      )
    })
    test.wait_for_events()

    test.socket.matter:__queue_receive({
      mock_device.id,
      DoorLock.client.commands.SetCredentialResponse:build_test_command_response(
        mock_device, 1,
        DoorLock.types.DlStatus.SUCCESS,
        1,  -- user_index
        nil -- next_redential_index
      ),
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.lockCodes.codeChanged(
          1 .. " set", {data = {codeName = "ST Remote Operation Code"}, state_change = true}
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.lockCodes.codeChanged("1 renamed", {state_change = true})
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.lockCodes
          .lockCodes(json.encode({["1"] = "ST Remote Operation Code"}), {visibility = {displayed = false}})
      )
    )
    mock_device:expect_metadata_update({
      profile = "base-lock",
      provisioning_state = "PROVISIONED"
    })
  end
)

test.register_coroutine_test(
  "External user creates space for COTA credential on a nonfunctional lock", function()
    test.socket.matter:__set_channel_ordering("relaxed")
    expect_kick_off_cota_process(mock_device)

    local next_credential_index = data_types.Null()
    test.socket.matter:__queue_receive({
      mock_device.id,
      DoorLock.client.commands.SetCredentialResponse:build_test_command_response(
        mock_device, 1,
        DoorLock.types.DlStatus.OCCUPIED,
        1,  -- user_index
        nil -- next_redential_index
      ),
    })
    mock_device:expect_metadata_update({
      profile = "nonfunctional-lock",
      provisioning_state = "NONFUNCTIONAL"
    })
    test.wait_for_events()

    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.server.events.LockUserChange:build_test_event_report(
          mock_device, 1, -- endpoint
          {
            lock_data_type = types.DlLockDataType.PIN,
            data_operation_type = types.DlDataOperationType.CLEAR,
            operation_source = types.DlOperationSource.KEYPAD,
            user_index = 0x1,
            data_index = 0x1, -- corresponds to credential_index
          }
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.lockCodes
          .codeChanged("1 deleted", {data = {codeName = "Code 1"}, state_change = true})
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
          capabilities.lockCodes.lockCodes(json.encode({}), {visibility = {displayed = false}})
      )
    )
    test.socket.matter:__expect_send({
      mock_device.id,
      DoorLock.server.commands.SetCredential(
        mock_device, 1, -- endpoint
        DoorLock.types.DlDataOperationType.ADD, -- operation_type
        DoorLock.types.DlCredential(
          {credential_type = DoorLock.types.DlCredentialType.PIN, credential_index = 1}
        ), -- credential
        test_credential_data, -- credential_data
        nil, -- user_index
        DoorLock.types.DlUserStatus.OCCUPIED_ENABLED, -- user_status
        DoorLock.types.DlUserType.REMOTE_ONLY_USER -- user_type
      )
    })
    test.wait_for_events()

    test.socket.matter:__queue_receive({
      mock_device.id,
      DoorLock.client.commands.SetCredentialResponse:build_test_command_response(
        mock_device, 1,
        DoorLock.types.DlStatus.SUCCESS,
        1,  -- user_index
        nil -- next_redential_index
      ),
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.lockCodes.codeChanged(
          1 .. " set", {data = {codeName = "ST Remote Operation Code"}, state_change = true}
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.lockCodes.codeChanged("1 renamed", {state_change = true})
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.lockCodes
          .lockCodes(json.encode({["1"] = "ST Remote Operation Code"}), {visibility = {displayed = false}})
      )
    )
    mock_device:expect_metadata_update({
      profile = "base-lock",
      provisioning_state = "PROVISIONED"
    })
  end
)

test.register_coroutine_test(
  "SetCredential for OCCUPIED credential index no space, but need full search", function()
    test.socket.matter:__set_channel_ordering("relaxed")
    expect_kick_off_cota_process(mock_device)

    local next_credential_index = 6
    test.socket.matter:__queue_receive({
      mock_device.id,
      DoorLock.client.commands.SetCredentialResponse:build_test_command_response(
        mock_device, 1,
        DoorLock.types.DlStatus.OCCUPIED,
        1, --user_index
        next_credential_index
      ),
    })
    test.socket.matter:__expect_send({
      mock_device.id,
      DoorLock.server.commands.SetCredential(
        mock_device, 1, -- endpoint
        DoorLock.types.DlDataOperationType.ADD, -- operation_type
        DoorLock.types.DlCredential(
          {credential_type = DoorLock.types.DlCredentialType.PIN, credential_index = next_credential_index}
        ), -- credential
        test_credential_data, -- credential_data
        nil, -- user_index
        DoorLock.types.DlUserStatus.OCCUPIED_ENABLED, -- user_status
        DoorLock.types.DlUserType.REMOTE_ONLY_USER -- user_type
      )
    })
    test.wait_for_events()

    test.socket.matter:__queue_receive({
      mock_device.id,
      DoorLock.client.commands.SetCredentialResponse:build_test_command_response(
        mock_device, 1,
        DoorLock.types.DlStatus.OCCUPIED,
        1,  --user_index
        nil --next_credential_index
      ),
    })
    test.socket.matter:__expect_send({
      mock_device.id,
      DoorLock.server.commands.SetCredential(
        mock_device, 1, -- endpoint
        DoorLock.types.DlDataOperationType.ADD, -- operation_type
        DoorLock.types.DlCredential(
          {credential_type = DoorLock.types.DlCredentialType.PIN, credential_index = 1}
        ), -- credential
        test_credential_data, -- credential_data
        nil, -- user_index
        DoorLock.types.DlUserStatus.OCCUPIED_ENABLED, -- user_status
        DoorLock.types.DlUserType.REMOTE_ONLY_USER -- user_type
      )
    })
  end
)

test.register_coroutine_test(
  "SetCredential for DUPLICATE credential index generates new credential and retries", function()
    test.socket.matter:__set_channel_ordering("relaxed")
    expect_kick_off_cota_process(mock_device)
    test.timer.__create_and_queue_test_time_advance_timer(4, "oneshot")

    local next_credential_index = 6
    test.socket.matter:__queue_receive({
      mock_device.id,
      DoorLock.client.commands.SetCredentialResponse:build_test_command_response(
        mock_device, 1,
        DoorLock.types.DlStatus.DUPLICATE,
        1, --user_index
        next_credential_index
      ),
    })
    test.wait_for_events()
    local new_credential_data = "87654321"
    mock_device:set_field("cotaCred", new_credential_data, {persist = true})
    test.socket.matter:__expect_send({
      mock_device.id,
      DoorLock.server.commands.SetCredential(
        mock_device, 1, -- endpoint
        DoorLock.types.DlDataOperationType.ADD, -- operation_type
        DoorLock.types.DlCredential(
          {credential_type = DoorLock.types.DlCredentialType.PIN, credential_index = 1}
        ), -- credential
        new_credential_data, -- credential_data
        nil, -- user_index
        DoorLock.types.DlUserStatus.OCCUPIED_ENABLED, -- user_status
        DoorLock.types.DlUserType.REMOTE_ONLY_USER -- user_type
      )
    })
    test.mock_time.advance_time(2)
  end
)


test.register_coroutine_test(
  "Deleted COTA cred is recreated", function()
    test.socket.matter:__set_channel_ordering("relaxed")
    expect_kick_off_cota_process(mock_device)
    test.socket.matter:__queue_receive({
      mock_device.id,
      DoorLock.client.commands.SetCredentialResponse:build_test_command_response(
        mock_device, 1,
        DoorLock.types.DlStatus.SUCCESS,
        1, --user_index
        4
      ),
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.lockCodes
          .codeChanged("1 set", {data = {codeName = "ST Remote Operation Code"}, state_change = true})
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.lockCodes.codeChanged("1 renamed", {state_change = true})
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.lockCodes
          .lockCodes(json.encode({["1"] = "ST Remote Operation Code"}), {visibility = {displayed = false}})
      )
    )
    test.wait_for_events()

    test.socket.capability:__queue_receive(
      {mock_device.id, {capability = capabilities.lockCodes.ID, command = "deleteCode", args = {1}}}
    )
    test.socket.matter:__expect_send({
      mock_device.id,
      DoorLock.server.commands.ClearCredential(
        mock_device,
        1,
        {credential_type = types.DlCredentialType.PIN, credential_index = 1}
      )
    })
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device.id,
      DoorLock.server.commands.ClearCredential:build_test_command_response(mock_device, 1),
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.lockCodes
          .codeChanged("1 deleted", {data = {codeName = "ST Remote Operation Code"}, state_change = true})
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
          capabilities.lockCodes.lockCodes(json.encode({}), {visibility = {displayed = false}})
      )
    )
    test.socket.matter:__expect_send({
      mock_device.id,
      DoorLock.server.commands.SetCredential(
        mock_device, 1, -- endpoint
        DoorLock.types.DlDataOperationType.ADD, -- operation_type
        DoorLock.types.DlCredential(
          {credential_type = DoorLock.types.DlCredentialType.PIN, credential_index = 1}
        ), -- credential
        test_credential_data, -- credential_data
        nil, -- user_index
        DoorLock.types.DlUserStatus.OCCUPIED_ENABLED, -- user_status
        DoorLock.types.DlUserType.REMOTE_ONLY_USER -- user_type
      )
    })
  end
)


test.run_registered_tests()
