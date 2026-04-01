-- Copyright 2023 SmartThings
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
local t_utils = require "integration_test.utils"
local clusters = require "st.matter.clusters"
local OctetString1 = require "st.matter.data_types.OctetString1"
local version = require "version"
if version.api < 20 then
  clusters.DoorLock = require "DoorLock"
end
local DoorLock = clusters.DoorLock

local enabled_optional_component_capability_pairs = {{
  "main",
  {
    capabilities.lockUsers.ID,
    capabilities.lockSchedules.ID,
    capabilities.lockAliro.ID
  }
}}
local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition(
    "lock-modular.yml",
    {enabled_optional_capabilities = enabled_optional_component_capability_pairs}
  ),
  manufacturer_info = {
    vendor_id = 0x135D,
    product_id = 0x00C1,
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
          feature_map = 0x2510, -- WDSCH & YDSCH & USR & ALIRO
        }
      },
      device_types = {
        { device_type_id = 0x000A, device_type_revision = 1 } -- Door Lock
      }
    }
  }
})

local function test_init()
  test.disable_startup_messages()
  test.mock_device.add_test_device(mock_device)
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main", capabilities.lockAlarm.alarm.clear({state_change = true}))
  )
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })
  local subscribe_request = DoorLock.attributes.LockState:subscribe(mock_device)
  subscribe_request:merge(DoorLock.attributes.OperatingMode:subscribe(mock_device))
  subscribe_request:merge(DoorLock.attributes.NumberOfTotalUsersSupported:subscribe(mock_device))
  subscribe_request:merge(DoorLock.attributes.NumberOfWeekDaySchedulesSupportedPerUser:subscribe(mock_device))
  subscribe_request:merge(DoorLock.attributes.NumberOfYearDaySchedulesSupportedPerUser:subscribe(mock_device))
  subscribe_request:merge(DoorLock.attributes.AliroReaderVerificationKey:subscribe(mock_device))
  subscribe_request:merge(DoorLock.attributes.AliroReaderGroupIdentifier:subscribe(mock_device))
  subscribe_request:merge(DoorLock.attributes.AliroReaderGroupSubIdentifier:subscribe(mock_device))
  subscribe_request:merge(DoorLock.attributes.AliroExpeditedTransactionSupportedProtocolVersions:subscribe(mock_device))
  subscribe_request:merge(DoorLock.attributes.AliroGroupResolvingKey:subscribe(mock_device))
  subscribe_request:merge(DoorLock.attributes.AliroSupportedBLEUWBProtocolVersions:subscribe(mock_device))
  subscribe_request:merge(DoorLock.attributes.AliroBLEAdvertisingVersion:subscribe(mock_device))
  subscribe_request:merge(DoorLock.attributes.NumberOfAliroCredentialIssuerKeysSupported:subscribe(mock_device))
  subscribe_request:merge(DoorLock.attributes.NumberOfAliroEndpointKeysSupported:subscribe(mock_device))
  subscribe_request:merge(DoorLock.attributes.FeatureMap:subscribe(mock_device))
  subscribe_request:merge(DoorLock.events.LockOperation:subscribe(mock_device))
  subscribe_request:merge(DoorLock.events.DoorLockAlarm:subscribe(mock_device))
  subscribe_request:merge(DoorLock.events.LockUserChange:subscribe(mock_device))
  test.socket["matter"]:__expect_send({mock_device.id, subscribe_request})

  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main", capabilities.lock.supportedLockValues({"locked", "unlocked", "not fully locked"}, {visibility = {displayed = false}}))
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main", capabilities.lock.supportedLockCommands({"lock", "unlock"}, {visibility = {displayed = false}}))
  )
  mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Handle received AliroReaderVerificationKey from Matter device.",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.attributes.AliroReaderVerificationKey:build_test_report_data(
          mock_device, 1,
          "\x04\xA9\xCB\xE4\x18\xEB\x09\x66\x16\x43\xE2\xA4\xA8\x46\xB8\xED\xFE\x27\x86\x98\x30\x2E\x9F\xB4\x3E\x9B\xFF\xD3\xE3\x10\xCC\x2C\x2C\x7F\xF4\x02\xE0\x6E\x40\xEA\x3C\xE1\x29\x43\x52\x73\x36\x68\x3F\xC5\xB1\xCB\x0C\x6A\x7C\x3F\x0B\x5A\xFF\x78\x35\xDF\x21\xC6\x24"
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockAliro.readerVerificationKey(
          "04a9cbe418eb09661643e2a4a846b8edfe278698302e9fb43e9bffd3e310cc2c2c7ff402e06e40ea3ce12943527336683fc5b1cb0c6a7c3f0b5aff7835df21c624",
          {visibility = {displayed = false}})
        )
    )
  end
)

test.register_coroutine_test(
  "Handle received AliroReaderGroupIdentifier from Matter device.",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.attributes.AliroReaderGroupIdentifier:build_test_report_data(
          mock_device, 1,
          "\xE2\x4F\x1B\x20\x5B\xA9\x23\xB3\x2C\xD1\x3D\xC0\x09\xE9\x93\xA8"
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockAliro.readerGroupIdentifier(
          "e24f1b205ba923b32cd13dc009e993a8",
          {visibility = {displayed = false}})
        )
    )
  end
)

test.register_coroutine_test(
  "Handle received AliroExpeditedTransactionSupportedProtocolVersions from Matter device.",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.attributes.AliroExpeditedTransactionSupportedProtocolVersions:build_test_report_data(
          mock_device, 1,
          {OctetString1("\x00\x09"), OctetString1("\x01\x00")}
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockAliro.expeditedTransactionProtocolVersions(
          {"0.9", "1.0"},
          {visibility = {displayed = false}})
        )
    )
  end
)

test.register_coroutine_test(
  "Handle received AliroSupportedBLEUWBProtocolVersions from Matter device.",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.attributes.AliroSupportedBLEUWBProtocolVersions:build_test_report_data(
          mock_device, 1,
          {OctetString1("\x00\x09"), OctetString1("\x01\x00")}
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockAliro.bleUWBProtocolVersions(
          {"0.9", "1.0"},
          {visibility = {displayed = false}})
        )
    )
  end
)

test.register_coroutine_test(
  "Handle received AliroReaderVerificationKey from Matter device.",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.attributes.NumberOfAliroCredentialIssuerKeysSupported:build_test_report_data(
          mock_device, 1,
          35
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockAliro.maxCredentialIssuerKeys(
          35,
          {visibility = {displayed = false}})
        )
    )
  end
)

test.register_coroutine_test(
  "Handle received AliroGroupResolvingKey from Matter device.",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.attributes.AliroGroupResolvingKey:build_test_report_data(
          mock_device, 1,
          "\xE2\x4F\x1B\x20\x5B\xA9\x23\xB3\x2C\xD1\x3D\xC0\x09\xE9\x93\xA8"
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockAliro.groupResolvingKey(
          "e24f1b205ba923b32cd13dc009e993a8",
          {visibility = {displayed = false}})
        )
    )
  end
)

test.register_coroutine_test(
  "Handle received AliroBLEAdvertisingVersion from Matter device.",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.attributes.AliroBLEAdvertisingVersion:build_test_report_data(
          mock_device, 1,
          1
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockAliro.bleAdvertisingVersion(
          "1",
          {visibility = {displayed = false}})
        )
    )
  end
)

test.register_coroutine_test(
  "Handle received NumberOfAliroEndpointKeysSupported from Matter device.",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.attributes.NumberOfAliroEndpointKeysSupported:build_test_report_data(
          mock_device, 1,
          10
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockAliro.maxEndpointKeys(
          10,
          {visibility = {displayed = false}})
        )
    )
  end
)

test.register_coroutine_test(
  "Handle Set Card Id command received from SmartThings.",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {
          capability = capabilities.lockAliro.ID,
          command = "setCardId",
          args = {"3icub18c8pr00"}
        },
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockAliro.cardId("3icub18c8pr00", {visibility = {displayed = false}})
      )
    )
  end
)

test.register_coroutine_test(
  "Handle Set Reader Config command received from SmartThings.",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {
          capability = capabilities.lockAliro.ID,
          command = "setReaderConfig",
          args = {
            "1a748a78566aaee985d9141730fa72bd83bf34e7b93072a0ca7b56a79b6debac",
            "041a748a78566aaee985d9141730fa72bd83bf34e7b93072a0ca7b56a79b6debac9493eded05a65701b5148517bd49a6c91c78ed6811543491eff1d257280ed809",
            "e24f1b205ba923b32cd13dc009e993a8",
            nil
          }
        },
      }
    )
    test.socket.matter:__expect_send(
      {
        mock_device.id,
        DoorLock.server.commands.SetAliroReaderConfig(
          mock_device, 1, -- endpoint
          "\x1A\x74\x8A\x78\x56\x6A\xAE\xE9\x85\xD9\x14\x17\x30\xFA\x72\xBD\x83\xBF\x34\xE7\xB9\x30\x72\xA0\xCA\x7B\x56\xA7\x9B\x6D\xEB\xAC",
          "\x04\x1A\x74\x8A\x78\x56\x6A\xAE\xE9\x85\xD9\x14\x17\x30\xFA\x72\xBD\x83\xBF\x34\xE7\xB9\x30\x72\xA0\xCA\x7B\x56\xA7\x9B\x6D\xEB\xAC\x94\x93\xED\xED\x05\xA6\x57\x01\xB5\x14\x85\x17\xBD\x49\xA6\xC9\x1C\x78\xED\x68\x11\x54\x34\x91\xEF\xF1\xD2\x57\x28\x0E\xD8\x09",
          "\xE2\x4F\x1B\x20\x5B\xA9\x23\xB3\x2C\xD1\x3D\xC0\x09\xE9\x93\xA8",
          nil
        ),
      }
    )
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.server.commands.SetAliroReaderConfig:build_test_command_response(
          mock_device, 1,
          DoorLock.types.DlStatus.SUCCESS -- status
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockAliro.commandResult(
          {commandName="setReaderConfig", statusCode="success"},
          {state_change=true, visibility={displayed=false}}
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Handle Set Endpoint Key command and Clear Endpoint Key command received from SmartThings.",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {
          capability = capabilities.lockAliro.ID,
          command = "setEndpointKey",
          args = {
            0,
            "vTNt0oPoHvIvwGMHa3AuXE3ZcY+Oocv5KZ+R0yveEag=",
            "nonEvictableEndpointKey",
            "041a748a78566aaee985d9141730fa72bd83bf34e7b93072a0ca7b56a79b6debac9493eded05a65701b5148517bd49a6c91c78ed6811543491eff1d257280ed809",
            "1f3acdf6-8930-45f7-ae3d-f0b47851c3e2"
          }
        },
      }
    )
    test.socket.matter:__expect_send(
      {
        mock_device.id,
        DoorLock.server.commands.SetCredential(
          mock_device, 1, -- endpoint
          DoorLock.types.DataOperationTypeEnum.ADD, -- operation_type
          DoorLock.types.CredentialStruct(
            {
              credential_type = DoorLock.types.CredentialTypeEnum.ALIRO_NON_EVICTABLE_ENDPOINT_KEY,
              credential_index = 1
            }
          ), -- credential
          "\x04\x1A\x74\x8A\x78\x56\x6A\xAE\xE9\x85\xD9\x14\x17\x30\xFA\x72\xBD\x83\xBF\x34\xE7\xB9\x30\x72\xA0\xCA\x7B\x56\xA7\x9B\x6D\xEB\xAC\x94\x93\xED\xED\x05\xA6\x57\x01\xB5\x14\x85\x17\xBD\x49\xA6\xC9\x1C\x78\xED\x68\x11\x54\x34\x91\xEF\xF1\xD2\x57\x28\x0E\xD8\x09", -- credential_data
          nil, -- user_index
          nil, -- user_status
          DoorLock.types.DlUserType.UNRESTRICTED_USER -- user_type
        ),
      }
    )
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.client.commands.SetCredentialResponse:build_test_command_response(
          mock_device, 1,
          DoorLock.types.DlStatus.SUCCESS, -- status
          1, -- user_index
          2 -- next_credential_index
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.users(
          {{userIndex=1, userType="adminMember"}},
          {visibility={displayed=false}}
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockAliro.credentials(
          {{
            keyId="vTNt0oPoHvIvwGMHa3AuXE3ZcY+Oocv5KZ+R0yveEag=",
            keyIndex=1,
            keyType="nonEvictableEndpointKey",
            userIndex=1
          }},
          {visibility={displayed=false}}
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockAliro.commandResult(
          {
            commandName="setEndpointKey",
            keyId="vTNt0oPoHvIvwGMHa3AuXE3ZcY+Oocv5KZ+R0yveEag=",
            requestId="1f3acdf6-8930-45f7-ae3d-f0b47851c3e2",
            statusCode="success",
            userIndex=1
          },
          {state_change=true, visibility={displayed=false}}
        )
      )
    )
    test.wait_for_events()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {
          capability = capabilities.lockAliro.ID,
          command = "clearEndpointKey",
          args = {1, "vTNt0oPoHvIvwGMHa3AuXE3ZcY+Oocv5KZ+R0yveEag=", "nonEvictableEndpointKey"}
        },
      }
    )
    test.socket.matter:__expect_send(
      {
        mock_device.id,
        DoorLock.server.commands.ClearCredential(
          mock_device, 1, -- endpoint
          DoorLock.types.CredentialStruct(
            {credential_type = DoorLock.types.CredentialTypeEnum.ALIRO_NON_EVICTABLE_ENDPOINT_KEY, credential_index = 1}
          )
        ),
      }
    )
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.server.commands.ClearCredential:build_test_command_response(
          mock_device, 1
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockAliro.credentials({}, {visibility={displayed=false}})
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.users({}, {visibility={displayed=false}})
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockSchedules.weekDaySchedules({}, {visibility={displayed=false}})
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockSchedules.yearDaySchedules({}, {visibility={displayed=false}})
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockAliro.commandResult(
          {
            commandName="clearEndpointKey",
            keyId="vTNt0oPoHvIvwGMHa3AuXE3ZcY+Oocv5KZ+R0yveEag=",
            statusCode="success",
            userIndex=1
          },
          {state_change=true, visibility={displayed=false}}
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Handle Set Issuer Key command and Clear Issuer Key command received from SmartThings.",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {
          capability = capabilities.lockAliro.ID,
          command = "setIssuerKey",
          args = {
            0,
            "041a748a78566aaee985d9141730fa72bd83bf34e7b93072a0ca7b56a79b6debac9493eded05a65701b5148517bd49a6c91c78ed6811543491eff1d257280ed809",
            "1f3acdf6-8930-45f7-ae3d-f0b47851c3e2"
          }
        },
      }
    )
    test.socket.matter:__expect_send(
      {
        mock_device.id,
        DoorLock.server.commands.SetCredential(
          mock_device, 1, -- endpoint
          DoorLock.types.DataOperationTypeEnum.ADD, -- operation_type
          DoorLock.types.CredentialStruct(
            {
              credential_type = DoorLock.types.CredentialTypeEnum.ALIRO_CREDENTIAL_ISSUER_KEY,
              credential_index = 1
            }
          ), -- credential
          "\x04\x1A\x74\x8A\x78\x56\x6A\xAE\xE9\x85\xD9\x14\x17\x30\xFA\x72\xBD\x83\xBF\x34\xE7\xB9\x30\x72\xA0\xCA\x7B\x56\xA7\x9B\x6D\xEB\xAC\x94\x93\xED\xED\x05\xA6\x57\x01\xB5\x14\x85\x17\xBD\x49\xA6\xC9\x1C\x78\xED\x68\x11\x54\x34\x91\xEF\xF1\xD2\x57\x28\x0E\xD8\x09", -- credential_data
          nil, -- user_index
          nil, -- user_status
          DoorLock.types.DlUserType.UNRESTRICTED_USER -- user_type
        ),
      }
    )
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.client.commands.SetCredentialResponse:build_test_command_response(
          mock_device, 1,
          DoorLock.types.DlStatus.SUCCESS, -- status
          1, -- user_index
          2 -- next_credential_index
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.users(
          {{userIndex=1, userType="adminMember"}},
          {visibility={displayed=false}}
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockAliro.credentials(
          {{
            keyIndex=1,
            keyType="issuerKey",
            userIndex=1
          }},
          {visibility={displayed=false}}
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockAliro.commandResult(
          {
            commandName="setIssuerKey",
            requestId="1f3acdf6-8930-45f7-ae3d-f0b47851c3e2",
            statusCode="success",
            userIndex=1
          },
          {state_change=true, visibility={displayed=false}}
        )
      )
    )
    test.wait_for_events()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {
          capability = capabilities.lockAliro.ID,
          command = "clearIssuerKey",
          args = {1, "1f3acdf6-8930-45f7-ae3d-f0b47851c3e2"}
        },
      }
    )
    test.socket.matter:__expect_send(
      {
        mock_device.id,
        DoorLock.server.commands.ClearCredential(
          mock_device, 1, -- endpoint
          DoorLock.types.CredentialStruct(
            {credential_type = DoorLock.types.CredentialTypeEnum.ALIRO_CREDENTIAL_ISSUER_KEY, credential_index = 1}
          )
        ),
      }
    )
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        DoorLock.server.commands.ClearCredential:build_test_command_response(
          mock_device, 1
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockAliro.credentials({}, {visibility={displayed=false}})
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockUsers.users({}, {visibility={displayed=false}})
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockSchedules.weekDaySchedules({}, {visibility={displayed=false}})
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockSchedules.yearDaySchedules({}, {visibility={displayed=false}})
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockAliro.commandResult(
          {
            commandName="clearIssuerKey",
            requestId="1f3acdf6-8930-45f7-ae3d-f0b47851c3e2",
            statusCode="success",
            userIndex=1
          },
          {state_change=true, visibility={displayed=false}}
        )
      )
    )
  end
)

test.run_registered_tests()
