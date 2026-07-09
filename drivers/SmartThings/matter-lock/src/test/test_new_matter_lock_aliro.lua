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

local FIXTURE_DER_B64 =
  "MHcCAQEEIHlEZiE0cRiQ+Jp+RAGQ/Rq8miEBQXfRQNeSlyNR0Cv1oAoGCCqGSM49AwEH" ..
  "oUQDQgAEeBuCTahXpt/rGLvVnOxjTlbmNYdKQF3vlHZYMK/LtISNUXJsJ1BfBX9nGgwY" ..
  "WlJ775K5woV3zzMW7X4dVV5C7Q=="
local EXPECTED_PRIV_HEX = "7944662134711890f89a7e440190fd1abc9a21014177d140d792972351d02bf5"
local EXPECTED_PUB_HEX  = "04781b824da857a6dfeb18bbd59cec634e56e635874a405def94765830afcbb48" ..
                           "48d51726c27505f057f671a0c185a527bef92b9c28577cf3316ed7e1d555e42ed"
local EXPECTED_GROUP_ID_HEX  = "64c8cce93255c4478d7aa05d83f3eaa2"

local base64 = require "base64"
local function default_generate_self_signed_cert(_opts)
  local der = base64.decode(FIXTURE_DER_B64)
  return {
    cert_pem = "-----BEGIN CERTIFICATE-----\nfake\n-----END CERTIFICATE-----",
    key_pem  = "-----BEGIN EC PRIVATE KEY-----\nfake\n-----END EC PRIVATE KEY-----",
    cert_der = der,
    key_der  = der,
  }
end
local security_stub = {
  generate_self_signed_cert = default_generate_self_signed_cert,
}
package.loaded["st.security"] = security_stub

local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local clusters = require "st.matter.clusters"
local cluster_base = require "st.matter.cluster_base"
local DoorLock = clusters.DoorLock
local OctetString1 = require "st.matter.data_types.OctetString1"
local lock_utils = require "lock_utils"
lock_utils.create_group_id_resolving_key = function()
  return EXPECTED_GROUP_ID_HEX
end

local key_id = "vTNt0oPoHvIvwGMHa3AuXE3ZcY+Oocv5KZ+R0yveEag="
local endpoint_key = "041a748a78566aaee985d9141730fa72bd83bf34e7b93072a0ca7b56a79b6debac9493eded05a65701b5148517bd49a6c91c78ed6811543491eff1d257280ed809"
local request_id = "1f3acdf6-8930-45f7-ae3d-f0b47851c3e2"

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

local DoorLockFeatureMapAttr = {ID = 0xFFFC, cluster = DoorLock.ID}
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
subscribe_request:merge(cluster_base.subscribe(mock_device, nil, DoorLockFeatureMapAttr.cluster, DoorLockFeatureMapAttr.ID))
subscribe_request:merge(DoorLock.events.LockOperation:subscribe(mock_device))
subscribe_request:merge(DoorLock.events.DoorLockAlarm:subscribe(mock_device))
subscribe_request:merge(DoorLock.events.LockUserChange:subscribe(mock_device))

local function test_init()
  test.disable_startup_messages()
  test.mock_device.add_test_device(mock_device)
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main", capabilities.lockAlarm.alarm.clear({state_change = true}))
  )
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })
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
          lock_utils.hex_string_to_octet_string(EXPECTED_PUB_HEX)
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockAliro.readerVerificationKey(EXPECTED_PUB_HEX, {visibility = {displayed = false}})
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
          lock_utils.hex_string_to_octet_string(EXPECTED_GROUP_ID_HEX)
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockAliro.readerGroupIdentifier(EXPECTED_GROUP_ID_HEX, {visibility = {displayed = false}})
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
          lock_utils.hex_string_to_octet_string(EXPECTED_GROUP_ID_HEX)
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockAliro.groupResolvingKey(EXPECTED_GROUP_ID_HEX, {visibility = {displayed = false}})
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
            EXPECTED_PRIV_HEX,
            EXPECTED_PUB_HEX,
            EXPECTED_GROUP_ID_HEX,
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
          lock_utils.hex_string_to_octet_string(EXPECTED_PRIV_HEX),
          lock_utils.hex_string_to_octet_string(EXPECTED_PUB_HEX),
          lock_utils.hex_string_to_octet_string(EXPECTED_GROUP_ID_HEX),
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
            0, -- user index
            key_id,
            "nonEvictableEndpointKey",
            endpoint_key,
            request_id
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
          lock_utils.hex_string_to_octet_string(endpoint_key), -- credential_data
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
            keyId=key_id,
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
            keyId=key_id,
            requestId=request_id,
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
          args = {1, key_id, "nonEvictableEndpointKey"}
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
            keyId=key_id,
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
  "Handle Set Endpoint Key command received from SmartThings and busy status",
  function()
    lock_utils.is_busy_state_set(mock_device)
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {
          capability = capabilities.lockAliro.ID,
          command = "setEndpointKey",
          args = {
            0, -- user index
            key_id,
            "nonEvictableEndpointKey",
            endpoint_key,
            request_id
          }
        },
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockAliro.commandResult(
          {
            commandName="setEndpointKey",
            keyId=key_id,
            requestId=request_id,
            statusCode="busy"
          },
          {state_change=true, visibility={displayed=false}}
        )
      )
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Handle Set Endpoint Key command received from SmartThings and user_index is occupied",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {
          capability = capabilities.lockAliro.ID,
          command = "setEndpointKey",
          args = {
            0, -- user index
            key_id,
            "nonEvictableEndpointKey",
            endpoint_key,
            request_id
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
          lock_utils.hex_string_to_octet_string(endpoint_key), -- credential_data
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
          DoorLock.types.DlStatus.OCCUPIED, -- status
          1, -- user_index
          2 -- next_credential_index
        ),
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
              credential_index = 2
            }
          ), -- credential
          lock_utils.hex_string_to_octet_string(endpoint_key), -- credential_data
          nil, -- user_index
          nil, -- user_status
          DoorLock.types.DlUserType.UNRESTRICTED_USER -- user_type
        ),
      }
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Handle Set Endpoint Key command received from SmartThings and user_index is occupied and next_credential_index is nil",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {
          capability = capabilities.lockAliro.ID,
          command = "setEndpointKey",
          args = {
            0, -- user index
            key_id,
            "nonEvictableEndpointKey",
            endpoint_key,
            request_id
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
          lock_utils.hex_string_to_octet_string(endpoint_key), -- credential_data
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
          DoorLock.types.DlStatus.OCCUPIED, -- status
          1, -- user_index
          nil -- next_credential_index
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockAliro.commandResult(
          {
            commandName="setEndpointKey",
            keyId=key_id,
            requestId=request_id,
            statusCode="resourceExhausted"
          },
          {state_change=true, visibility={displayed=false}}
        )
      )
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Handle Set Endpoint Key command received from SmartThings and user_index is failure",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {
          capability = capabilities.lockAliro.ID,
          command = "setEndpointKey",
          args = {
            0, -- user index
            key_id,
            "nonEvictableEndpointKey",
            endpoint_key,
            request_id
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
          lock_utils.hex_string_to_octet_string(endpoint_key), -- credential_data
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
          DoorLock.types.DlStatus.FAILURE, -- status
          1, -- user_index
          2 -- next_credential_index
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockAliro.commandResult(
          {
            commandName="setEndpointKey",
            keyId=key_id,
            requestId=request_id,
            statusCode="failure"
          },
          {state_change=true, visibility={displayed=false}}
        )
      )
    )
  end,
  {
     min_api_version = 17
  }
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
            endpoint_key,
            request_id
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
          lock_utils.hex_string_to_octet_string(endpoint_key), -- credential_data
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
            requestId=request_id,
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
          args = {1, request_id}
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
            requestId=request_id,
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
  "Handle Set Issuer Key command received from SmartThings and busy status",
  function()
    lock_utils.is_busy_state_set(mock_device)
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {
          capability = capabilities.lockAliro.ID,
          command = "setIssuerKey",
          args = {
            0,
            endpoint_key,
            request_id
          }
        },
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockAliro.commandResult(
          {
            commandName="setIssuerKey",
            requestId=request_id,
            statusCode="busy"
          },
          {state_change=true, visibility={displayed=false}}
        )
      )
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Handle Set Issuer Key command received from SmartThings and user_index is occupied",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {
          capability = capabilities.lockAliro.ID,
          command = "setIssuerKey",
          args = {
            0,
            endpoint_key,
            request_id
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
          lock_utils.hex_string_to_octet_string(endpoint_key), -- credential_data
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
          DoorLock.types.DlStatus.OCCUPIED, -- status
          1, -- user_index
          2 -- next_credential_index
        ),
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
              credential_index = 2
            }
          ), -- credential
          lock_utils.hex_string_to_octet_string(endpoint_key), -- credential_data
          nil, -- user_index
          nil, -- user_status
          DoorLock.types.DlUserType.UNRESTRICTED_USER -- user_type
        ),
      }
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Handle Set Issuer Key command received from SmartThings and user_index is occupied and next_credential_index is nil",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {
          capability = capabilities.lockAliro.ID,
          command = "setIssuerKey",
          args = {
            0,
            endpoint_key,
            request_id
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
          lock_utils.hex_string_to_octet_string(endpoint_key), -- credential_data
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
          DoorLock.types.DlStatus.OCCUPIED, -- status
          1, -- user_index
          nil -- next_credential_index
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockAliro.commandResult(
          {
            commandName="setIssuerKey",
            requestId=request_id,
            statusCode="resourceExhausted"
          },
          {state_change=true, visibility={displayed=false}}
        )
      )
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Handle Set Issuer Key command received from SmartThings and user_index is failure",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {
          capability = capabilities.lockAliro.ID,
          command = "setIssuerKey",
          args = {
            0,
            endpoint_key,
            request_id
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
          lock_utils.hex_string_to_octet_string(endpoint_key), -- credential_data
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
          DoorLock.types.DlStatus.FAILURE, -- status
          1, -- user_index
          2 -- next_credential_index
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockAliro.commandResult(
          {
            commandName="setIssuerKey",
            requestId=request_id,
            statusCode="failure"
          },
          {state_change=true, visibility={displayed=false}}
        )
      )
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "set_reader_config should send SetAliroReaderConfig command on device init",
  function()
    mock_device:set_field(lock_utils.ALIRO_READER_CONFIG_UPDATED, nil, {persist = true})
    mock_device:set_field(lock_utils.BUSY_STATE, false, {persist = true})
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({ profile = t_utils.get_profile_definition("lock.yml")}))
    test.socket["matter"]:__expect_send({mock_device.id, subscribe_request})
    test.socket.matter:__expect_send(
      {
        mock_device.id,
        DoorLock.server.commands.SetAliroReaderConfig(
          mock_device, 1,
          lock_utils.hex_string_to_octet_string(EXPECTED_PRIV_HEX),
          lock_utils.hex_string_to_octet_string(EXPECTED_PUB_HEX),
          lock_utils.hex_string_to_octet_string(EXPECTED_GROUP_ID_HEX),
          nil
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.lockAlarm.alarm.clear({state_change = true}))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.lockAlarm.supportedAlarmValues({"unableToLockTheDoor"}, {visibility = {displayed = false}}))
    )
  end
)

test.register_coroutine_test(
  "Set Reader Config command sets busy state in command result when busy",
  function()
    mock_device:set_field(lock_utils.ALIRO_READER_CONFIG_UPDATED, nil, {persist = true})
    lock_utils.is_busy_state_set(mock_device)
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({ profile = t_utils.get_profile_definition("lock.yml")}))
    test.socket["matter"]:__expect_send({mock_device.id, subscribe_request})
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.lockAliro.commandResult(
          {
            commandName="setReaderConfig",
            statusCode="busy"
          },
          {state_change=true, visibility={displayed=false}}
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.lockAlarm.alarm.clear({state_change = true}))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.lockAlarm.supportedAlarmValues({"unableToLockTheDoor"}, {visibility = {displayed = false}}))
    )
  end
)

test.run_registered_tests()
