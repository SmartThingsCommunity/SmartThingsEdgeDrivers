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
          feature_map = 0x0101, -- PIN & USR
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

  local next_credential_index = 2
  test.socket.matter:__queue_receive(
    {
      dev.id,
      DoorLock.client.commands.GetCredentialStatusResponse:build_test_command_response(
        dev, 1, -- endpoint
        true, --credential exists
        1,  --user_index
        nil, --creator fabric index
        nil, --last modified fabric index
        next_credential_index
      ),
    }
  )
  test.socket.capability:__expect_send(
    dev:generate_test_message(
      "main", capabilities.lockCodes
        .codeChanged("1 set", {data = {codeName = "Code 1"}, state_change = true})
    )
  )
  test.socket.capability:__expect_send(
    dev:generate_test_message(
      "main", capabilities.lockCodes.lockCodes(
        json.encode({["1"] = "Code 1"}), {visibility = {displayed = false}}
      )
    )
  )
  local credential1 = types.DlCredential(
                      {
    credential_type = DoorLock.types.DlCredentialType.PIN,
    credential_index = next_credential_index,
  })
  test.socket.matter:__expect_send(
    {dev.id, DoorLock.server.commands.GetCredentialStatus(dev, 1, credential1)}
  )
  test.wait_for_events()

  test.socket.capability:__expect_send(
    dev:generate_test_message(
      "main", capabilities.lockCodes
        .codeChanged("2 set", {data = {codeName = "Code 2"}, state_change = true})
    )
  )
  test.socket.capability:__expect_send(
    dev:generate_test_message(
      "main", capabilities.lockCodes.lockCodes(
        json.encode({["1"] = "Code 1", ["2"] = "Code 2"}), {visibility = {displayed = false}}
      )
    )
  )

  test.socket.matter:__queue_receive(
    {
      dev.id,
      DoorLock.client.commands.GetCredentialStatusResponse:build_test_command_response(
        dev, 1, -- endpoint
        true, --credential exists
        1,    --user_index
        nil,  --creator fabric index
        nil,  --last modified fabric index
        nil   --next credential index
      ),
    }
  )

  test.socket.capability:__expect_send(
    dev:generate_test_message(
      "main", capabilities.lockCodes.scanCodes("Complete", {visibility = {displayed = false}})
    )
  )
  test.socket.capability:__expect_send(
    dev:generate_test_message(
      "main", capabilities.lockCodes.lockCodes(
        json.encode({["1"] = "Code 1", ["2"] = "Code 2"}),
          {visibility = {displayed = false}}
      )
    )
  )
end

local function init_code_slot(slot_number, name, device)
  test.socket.capability:__queue_receive(
    {
      device.id,
      {
        capability = capabilities.lockCodes.ID,
        command = "setCode",
        args = {slot_number, "1234", name},
      },
    }
  )

  local credential = DoorLock.types.DlCredential(
                       {
      credential_type = DoorLock.types.DlCredentialType.PIN,
      credential_index = slot_number,
    }
                     )
  test.socket.matter:__expect_send(
    {
      device.id,
      DoorLock.server.commands.SetCredential(
        mock_device, 1, -- endpoint
        DoorLock.types.DlDataOperationType.ADD, -- operation_type
        credential, -- credential
        "1234", -- credential_data
        nil, -- user_index
        DoorLock.types.DlUserStatus.OCCUPIED_ENABLED, -- user_status
        DoorLock.types.DlUserType.UNRESTRICTED_USER -- user_type
      ),
    }
  )

  test.wait_for_events()
  test.socket.matter:__queue_receive(
    {
      mock_device.id,
      DoorLock.client.commands.SetCredentialResponse:build_test_command_response(
        mock_device, 1, -- endpoint_id
        DoorLock.types.DlStatus.SUCCESS, -- status
        slot_number, -- user_index
        slot_number + 1 -- next_credential_index
      ),
    }
  )
  test.socket.capability:__expect_send(
    device:generate_test_message(
      "main", capabilities.lockCodes.codeChanged(
        slot_number .. " set", {data = {codeName = name}, state_change = true}
      )
    )
  )
end

test.register_coroutine_test(
  "Added should configure all necessary attributes and begin reading codes", function()
    test.socket.matter:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
    )
    local req = DoorLock.attributes.MaxPINCodeLength:read(mock_device, 1)
    req:merge(DoorLock.attributes.MinPINCodeLength:read(mock_device, 1))
    req:merge(DoorLock.attributes.NumberOfPINUsersSupported:read(mock_device, 1))
    test.socket.matter:__expect_send({mock_device.id, req})
    expect_reload_all_codes_messages(mock_device)
  end
)

local credential = DoorLock.types.DlCredential(
                     {credential_type = DoorLock.types.DlCredentialType.PIN, credential_index = 1}
                   )
test.register_coroutine_test(
  "Credential status response reporting should be handled", function()
    init_code_slot(1, "initialName", mock_device)
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.lockCodes.lockCodes(
          json.encode({["1"] = "initialName"}), {visibility = {displayed = false}}
        )
      )
    )
  end
)

test.register_message_test(
  "Min lock code length report should be handled", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        DoorLock.attributes.MinPINCodeLength:build_test_report_data(mock_device, 1, 4),
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message(
        "main",
        capabilities.lockCodes.minCodeLength(4, {visibility = {displayed = false}})
      ),
    },
  }
)

test.register_message_test(
  "Max lock code length report should be handled", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        DoorLock.attributes.MaxPINCodeLength:build_test_report_data(mock_device, 1, 4),
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message(
        "main",
        capabilities.lockCodes.maxCodeLength(4, {visibility = {displayed = false}})
      ),
    },
  }
)

test.register_message_test(
  "Max user code number report should be handled", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        DoorLock.attributes.NumberOfPINUsersSupported:build_test_report_data(mock_device, 1, 16),
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message(
        "main",
        capabilities.lockCodes.maxCodes(16, {visibility = {displayed = false}})
      ),
    },
  }
)

test.register_coroutine_test(
  "Reloading all codes of an unconfigured lock should generate correct attribute checks", function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = capabilities.lockCodes.ID, command = "reloadAllCodes", args = {}},
      }
    )
    expect_reload_all_codes_messages(mock_device)
  end
)

test.register_coroutine_test(
  "Requesting a user code should be handled", function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = capabilities.lockCodes.ID, command = "requestCode", args = {1}},
      }
    )
    local credential = {credential_type = types.DlCredentialType.PIN, credential_index = 1}
    test.socket.matter:__expect_send(
      {mock_device.id, DoorLock.server.commands.GetCredentialStatus(mock_device, 1, credential)}
    )
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.client.commands.GetCredentialStatusResponse:build_test_command_response(
          mock_device, 1, -- endpoint
          true, -- credential_exists
          1, -- user_index
          nil, -- creator_fabric_index
          nil, -- last_modified_fabric_index
          20 -- next_credential_index
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.lockCodes
          .codeChanged("1 set", {data = {codeName = "Code 1"}, state_change = true})
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.lockCodes.lockCodes(
          json.encode({["1"] = "Code 1"}), {visibility = {displayed = false}}
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Deleting a user code should be handled", function()
    init_code_slot(1, "initialName", mock_device)
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.lockCodes.lockCodes(
          json.encode({["1"] = "initialName"}), {visibility = {displayed = false}}
        )
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
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.server.commands.ClearCredential:build_test_command_response(mock_device, 1),
      }
    )

    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.lockCodes
          .codeChanged("1 deleted", {data = {codeName = "initialName"}, state_change = true})
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
          capabilities.lockCodes.lockCodes(json.encode({}), {visibility = {displayed = false}})
      )
    )
  end
)

test.register_coroutine_test(
  "Setting a user code should result in the named code changed event firing", function()
    local code_slot = 1
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {
          capability = capabilities.lockCodes.ID,
          command = "setCode",
          args = {code_slot, "1234", "test"},
        },
      }
    )
    test.socket.matter:__expect_send(
      {
        mock_device.id,
        DoorLock.server.commands.SetCredential(
          mock_device, 1, -- endpoint
          DoorLock.types.DlDataOperationType.ADD, -- operation_type
          DoorLock.types.DlCredential(
            {credential_type = DoorLock.types.DlCredentialType.PIN, credential_index = code_slot}
          ), -- credential
          "1234", -- credential_data
          nil, -- user_index
          DoorLock.types.DlUserStatus.OCCUPIED_ENABLED, -- user_status
          DoorLock.types.DlUserType.UNRESTRICTED_USER -- user_type
        ),
      }
    )
    test.wait_for_events()

    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.client.commands.SetCredentialResponse:build_test_command_response(
          mock_device, 1, -- endpoint_id
          DoorLock.types.DlStatus.SUCCESS, -- status
          1, -- user_index
          2 -- next_credential_index
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.lockCodes
          .codeChanged("1 set", {data = {codeName = "test"}, state_change = true})
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.lockCodes
          .lockCodes(json.encode({["1"] = "test"}), {visibility = {displayed = false}})
      )
    )
  end
)

test.register_coroutine_test(
  "Setting a user code name should be handled", function()
    init_code_slot(1, "initialName", mock_device)
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.lockCodes.lockCodes(
          json.encode({["1"] = "initialName"}), {visibility = {displayed = false}}
        )
      )
    )
    test.wait_for_events()

    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = capabilities.lockCodes.ID, command = "nameSlot", args = {1, "foo"}},
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.lockCodes.codeChanged("1 renamed", {state_change = true})
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.lockCodes
          .lockCodes(json.encode({["1"] = "foo"}), {visibility = {displayed = false}})
      )
    )
  end
)
test.register_coroutine_test(
  "Setting a user code name via setCode should be handled", function()
    init_code_slot(1, "initialName", mock_device)
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.lockCodes.lockCodes(
          json.encode({["1"] = "initialName"}), {visibility = {displayed = false}}
        )
      )
    )
    test.wait_for_events()

    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = capabilities.lockCodes.ID, command = "setCode", args = {1, "", "foo"}},
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.lockCodes.codeChanged("1 renamed", {state_change = true})
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.lockCodes
          .lockCodes(json.encode({["1"] = "foo"}), {visibility = {displayed = false}})
      )
    )
  end
)

test.register_message_test(
  "The lock reporting a single PIN credential has been added should be handled", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        DoorLock.server.events.LockUserChange:build_test_event_report(
          mock_device, 1, -- endpoint
          {
            lock_data_type = types.DlLockDataType.PIN,
            data_operation_type = types.DlDataOperationType.ADD,
            operation_source = types.DlOperationSource.KEYPAD,
            user_index = 0x1,
            data_index = 0x1, -- corresponds to credential_index on the user due to a cred being added
          }
        ),
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message(
        "main", capabilities.lockCodes
          .codeChanged("1 set", {data = {codeName = "Code 1"}, state_change = true})
      ),
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message(
        "main", capabilities.lockCodes.lockCodes(
          json.encode({["1"] = "Code 1"}), {visibility = {displayed = false}}
        )
      ),
    },
  }
)

test.register_coroutine_test(
  "The lock reporting a code has been deleted should be handled", function()
    init_code_slot(1, "Code 1", mock_device)
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.lockCodes.lockCodes(
          json.encode({["1"] = "Code 1"}), {visibility = {displayed = false}}
        )
      )
    )
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
  end
)

test.register_coroutine_test(
  "The lock reporting that all users have been deleted should be handled", function()
    init_code_slot(1, "Code 1", mock_device)
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.lockCodes.lockCodes(
          json.encode({["1"] = "Code 1"}), {visibility = {displayed = false}}
        )
      )
    )
    test.wait_for_events()
    init_code_slot(2, "Code 2", mock_device)
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.lockCodes.lockCodes(
          json.encode({["1"] = "Code 1", ["2"] = "Code 2"}), {visibility = {displayed = false}}
        )
      )
    )
    test.wait_for_events()
    init_code_slot(3, "Code 3", mock_device)
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.lockCodes.lockCodes(
          json.encode({["1"] = "Code 1", ["2"] = "Code 2", ["3"] = "Code 3"}),
            {visibility = {displayed = false}}
        )
      )
    )

    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.server.events.LockUserChange:build_test_event_report(
          mock_device, 1, -- endpoint
          {
            lock_data_type = types.DlLockDataType.USER_INDEX,
            data_operation_type = types.DlDataOperationType.CLEAR,
            operation_source = types.DlOperationSource.KEYPAD,
            user_index = 0xFFFE,
          }
        ),
      }
    )

    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.lockCodes
          .codeChanged("1 deleted", {data = {codeName = "Code 1"}, state_change = true})
      )
    )

    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.lockCodes
          .codeChanged("2 deleted", {data = {codeName = "Code 2"}, state_change = true})
      )
    )

    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.lockCodes
          .codeChanged("3 deleted", {data = {codeName = "Code 3"}, state_change = true})
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
          capabilities.lockCodes.lockCodes(json.encode({}), {visibility = {displayed = false}})
      )
    )
    test.wait_for_events()
  end
)

test.run_registered_tests()
