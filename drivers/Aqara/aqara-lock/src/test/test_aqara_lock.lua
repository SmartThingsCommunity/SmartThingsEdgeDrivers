local test = require "integration_test"
local t_utils = require "integration_test.utils"
local capabilities = require "st.capabilities"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local remoteControlStatus = capabilities.remoteControlStatus
local lockCredentialInfo = capabilities["stse.lockCredentialInfo"]
test.add_package_capability("lockCredentialInfo.yaml")
local Battery = capabilities.battery
local Lock = capabilities.lock
local TamperAlert = capabilities.tamperAlert

local PRI_CLU = 0xFCC0
local PRI_ATTR = 0xFFF3
local MFG_CODE = 0x115F

local HOST_COUNT = "__host_count"

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("aqara-lock-battery.yml"),
    fingerprinted_endpoint_id = 0x01,
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "Lumi",
        model = "aqara.lock.akr011",
        server_clusters = { PRI_CLU }
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Handle added lifecycle - no host user",
  function()
    mock_device:set_field(HOST_COUNT, 0, { persist = true })
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })

    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      remoteControlStatus.remoteControlEnabled('false', { visibility = { displayed = false } })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", Battery.battery(100)))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      TamperAlert.tamper("clear", { visibility = { displayed = false } })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", Lock.lock("locked")))
  end
)

test.register_coroutine_test(
  "Handle added lifecycle - only regular user",
  function()
    mock_device:set_field(HOST_COUNT, 1, { persist = true })
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })

    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      remoteControlStatus.remoteControlEnabled('true', { visibility = { displayed = false } })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", Battery.battery(100)))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      TamperAlert.tamper("clear", { visibility = { displayed = false } })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", Lock.lock("locked")))
  end
)

test.register_coroutine_test(
  "credential_utils.sync_all_credential_info",
  function()
    local credentialInfoData = {
      {
        { credentialId = 1, credentialType = "keypad",      userId = "1", userLabel = "user1", userType = "host" },
        { credentialId = 2, credentialType = "fingerprint", userId = "2", userLabel = "user2", userType = "regularUser" }
      }
    }
    local credentialInfoData_copy = {
      { credentialId = 1, credentialType = "keypad",      userId = "1", userLabel = "user1", userType = "host" },
      { credentialId = 2, credentialType = "fingerprint", userId = "2", userLabel = "user2", userType = "regularUser" }
    }
    mock_device:set_field(HOST_COUNT, 0, { persist = true })
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = lockCredentialInfo.ID, component = "main", command = "syncAll", args = credentialInfoData }
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      remoteControlStatus.remoteControlEnabled('true', { visibility = { displayed = false } })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      lockCredentialInfo.credentialInfo(credentialInfoData_copy, { visibility = { displayed = false } })))
  end
)

test.register_coroutine_test(
  "credential_utils.upsert_credential_info(host user)",
  function()
    local credentialInfoData = {
      { credentialId = 1, credentialType = "keypad", userId = "1", userLabel = "user1", userType = "host" }
    }
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = lockCredentialInfo.ID, component = "main", command = "upsert", args = { credentialInfoData } } })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      remoteControlStatus.remoteControlEnabled('true', { visibility = { displayed = false } })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      lockCredentialInfo.credentialInfo(credentialInfoData, { visibility = { displayed = false } })))
  end
)

test.register_coroutine_test(
  "credential_utils.upsert_credential_info(regular user)",
  function()
    local credentialInfoData = {
      { credentialId = 1, credentialType = "keypad", userId = "1", userLabel = "user1", userType = "regularUser" }
    }
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = lockCredentialInfo.ID, component = "main", command = "upsert", args = credentialInfoData } })
  end
)

test.register_coroutine_test(
  "credential_utils.delete_user",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = lockCredentialInfo.ID, component = "main", command = "deleteUser", args = { userId = "3" } } })
  end
)

test.register_coroutine_test(
  "credential_utils.delete_credential",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = lockCredentialInfo.ID, component = "main", command = "deleteCredential", args = { credentialId = "1" } } })
  end
)

test.register_coroutine_test(
  "lock_state_handler - shared_key is nil",
  function()
    local attr_report_data = {
      { PRI_ATTR, data_types.OctetString.ID, "\x93\x15\xAA\xFE\x78\xEE\x3E\x81\x9A\x06\xE3\x9A\x62\xD3\xB1\xF1\xD4\x64\x8C\x16\x66\xAB\xE1\x69\x89\x8C\x04\x56\x8D\xAD\xEA\xDE\xF8" }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRI_CLU, attr_report_data, MFG_CODE)
    })
    test.socket.zigbee:__expect_send({ mock_device.id, cluster_base.write_manufacturer_specific_attribute(mock_device,
      PRI_CLU, PRI_ATTR, MFG_CODE, data_types.OctetString, "\x2B") })
  end
)

test.run_registered_tests()
