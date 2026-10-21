-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-- DEBUG ONLY, do not merge: tests for debug_master_code.lua

local test = require "integration_test"
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local json = require "dkjson"
local constants = require "lock_utils.constants"

local PowerConfiguration = clusters.PowerConfiguration
local Alarm = clusters.Alarms
local DoorLock = clusters.DoorLock
local DoorLockUserStatus = DoorLock.types.DrlkUserStatus
local DoorLockUserType = DoorLock.types.DrlkUserType

local mock_device = test.mock_device.build_test_zigbee_device({
  profile = t_utils.get_profile_definition("base-lock.yml"),
  zigbee_endpoints = {
    [1] = { id = 1, manufacturer = "Yale", server_clusters = { 0x0001 } }
  }
})

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

local function test_init_migrated()
  test.disable_startup_messages()
  test.mock_device.add_test_device(mock_device)
  mock_device:set_field(constants.DRIVER_STATE.SLGA_MIGRATED, true, {})
end

local function master_code_response(user_status)
  return {
    mock_device.id,
    DoorLock.client.commands.GetPINCodeResponse.build_test_rx(
      mock_device, 0x00, user_status, DoorLockUserType.MASTER_USER, "123456")
  }
end

local function receive_refresh()
  test.socket.capability:__queue_receive({ mock_device.id,
    { capability = capabilities.refresh.ID, component = "main", command = "refresh", args = {} }
  })
  test.socket.zigbee:__expect_send({ mock_device.id, PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device) })
  test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.LockState:read(mock_device) })
  test.socket.zigbee:__expect_send({ mock_device.id, Alarm.attributes.AlarmCount:read(mock_device) })
end

local function expect_master_code_read()
  test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.SendPINOverTheAir:write(mock_device, true) })
  test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.server.commands.GetPINCode(mock_device, 0) })
end

test.register_coroutine_test(
  "legacy: refresh reads slot 0, and the response is logged without being added to lockCodes",
  function()
    receive_refresh()
    expect_master_code_read()
    test.wait_for_events()

    -- no lockCodes events are expected for the requested slot 0 response
    test.socket.zigbee:__queue_receive(master_code_response(DoorLockUserStatus.OCCUPIED_ENABLED))
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "legacy: a slot 0 response that was not requested by the debug read is processed normally",
  function()
    test.socket.zigbee:__queue_receive(master_code_response(DoorLockUserStatus.OCCUPIED_ENABLED))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.lockCodes.codeChanged("0 set", { data = { codeName = "Code 0" }, state_change = true })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.lockCodes.lockCodes(json.encode({ ["0"] = "Code 0" }), { visibility = { displayed = false } })))
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "migrated: refresh reads slot 0, and the response does not change the users or credentials",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = capabilities.refresh.ID, component = "main", command = "refresh", args = {} }
    })
    test.socket.zigbee:__expect_send({ mock_device.id, PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.LockState:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, Alarm.attributes.AlarmCount:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.MaxPINCodeLength:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.MinPINCodeLength:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.NumberOfPINUsersSupported:read(mock_device) })
    expect_master_code_read()
    test.wait_for_events()

    test.socket.zigbee:__queue_receive(master_code_response(DoorLockUserStatus.AVAILABLE))
    test.wait_for_events()
  end,
  { test_init = test_init_migrated }
)

test.run_registered_tests()
