local test = require "integration_test"
local t_utils = require "integration_test.utils"
local capabilities = require "st.capabilities"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local remoteControlStatus = capabilities.remoteControlStatus
local antiLockStatus = capabilities["stse.antiLockStatus"]
test.add_package_capability("antiLockStatus.yaml")
local lockCredentialInfo = capabilities["stse.lockCredentialInfo"]
test.add_package_capability("lockCredentialInfo.yaml")
local lockAlarm = capabilities["lockAlarm"]
test.add_package_capability("lockAlarm.yaml")
local Battery = capabilities.battery
local BatteryLevel = capabilities.batteryLevel
local Lock = capabilities.lock

local PRI_CLU = 0xFCC0
local PRI_ATTR = 0xFFF3
local MFG_CODE = 0x115F

local HOST_COUNT = "__host_count"
local PERSIST_DATA = "__persist_area"

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("aqara-lock-battery.yml"),
    fingerprinted_endpoint_id = 0x01,
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "Lumi",
        model = "aqara.lock.akr001",
        server_clusters = { PRI_CLU }
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  local SUPPORTED_ALARM_VALUES = { "damaged", "forcedOpeningAttempt", "unableToLockTheDoor", "notClosedForALongTime",
  "highTemperature", "attemptsExceeded" }
  test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    lockAlarm.supportedAlarmValues(SUPPORTED_ALARM_VALUES, { visibility = { displayed = false } })))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    Lock.supportedUnlockDirections({"fromInside", "fromOutside"}, { visibility = { displayed = false } })))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", Battery.type("AA")))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", BatteryLevel.type("AA")))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", Battery.quantity(6)))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", BatteryLevel.quantity(6)))
  local credentialInfoData = {
    { credentialId = 1, credentialType = "keypad", userId = "1", userLabel = "june", userType = "host" }
  }
  mock_device:set_field(PERSIST_DATA, credentialInfoData, { persist = true })
  test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    lockCredentialInfo.credentialInfo(credentialInfoData, { visibility = { displayed = false } })))
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Handle added lifecycle - only regular user",
  function()
    mock_device:set_field(HOST_COUNT, 1, { persist = true })
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })

    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      remoteControlStatus.remoteControlEnabled('true', { visibility = { displayed = false } })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", Battery.battery(100)))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", BatteryLevel.battery("normal")))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      lockAlarm.alarm.clear({ visibility = { displayed = false } })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      antiLockStatus.antiLockStatus('unknown', { visibility = { displayed = false } })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", Lock.lock("locked")))
  end
)

test.run_registered_tests()
