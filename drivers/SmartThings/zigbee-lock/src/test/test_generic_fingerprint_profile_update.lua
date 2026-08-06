-- Copyright 2023 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-- Mock out globals
local test = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"

local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local PowerConfiguration = clusters.PowerConfiguration
local DoorLock = clusters.DoorLock
local Alarm = clusters.Alarms

local mock_device = test.mock_device.build_test_zigbee_device(
    { profile = t_utils.get_profile_definition("lock-battery.yml") }
)
zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "If lock codes are not supported by the profile but the lock supports them, switch profiles",
  function ()
    test.socket.capability:__queue_receive({mock_device.id, { capability = "refresh", component = "main", command = "refresh", args = {} }})

    test.socket.zigbee:__expect_send({mock_device.id, PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device)})
    test.socket.zigbee:__expect_send({mock_device.id, DoorLock.attributes.LockState:read(mock_device)})
    test.socket.zigbee:__expect_send({mock_device.id, Alarm.attributes.AlarmCount:read(mock_device)})
    test.socket.zigbee:__expect_send({mock_device.id, DoorLock.attributes.NumberOfPINUsersSupported:read(mock_device)})
    test.socket.zigbee:__queue_receive({mock_device.id, DoorLock.attributes.NumberOfPINUsersSupported:build_test_attr_report(mock_device, 8)})
    mock_device:expect_metadata_update({profile = "base-lock"})

    test.wait_for_events()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({ profile = t_utils.get_profile_definition("base-lock.yml") }))
    test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCodes.migrated(true,  { visibility = { displayed = false } })))
    test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.lockCredentials.supportedCredentials({"pin"},  { visibility = { displayed = false } })))
    -- inject_capability_command(refresh) is called inline by info_changed
    test.socket.zigbee:__expect_send({mock_device.id, PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device)})
    test.socket.zigbee:__expect_send({mock_device.id, DoorLock.attributes.LockState:read(mock_device)})
    test.socket.zigbee:__expect_send({mock_device.id, Alarm.attributes.AlarmCount:read(mock_device)})
    test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.MaxPINCodeLength:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.MinPINCodeLength:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.NumberOfPINUsersSupported:read(mock_device) })
  end,
  {
     min_api_version = 17
  }
)

test.run_registered_tests()
