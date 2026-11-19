-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-- Mock out globals
local test = require "integration_test"
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local PowerConfiguration = clusters.PowerConfiguration
local consts = require "lock_utils.constants"

local mock_device = test.mock_device.build_test_zigbee_device({
  profile = t_utils.get_profile_definition("base-lock.yml"),
  zigbee_endpoints = {
    [1] = {
      id = 1,
      manufacturer = "ASSA ABLOY iRevo",
      model = "c700000202",
      server_clusters = { 0x0001 }
    }
  }
})

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
  mock_device:set_field(consts.DRIVER_STATE.SLGA_MIGRATED, true, { persist = true })
  -- init emits migrated state for SLGA-migrated devices
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.migrated(true, { visibility = { displayed = false } })))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCredentials.supportedCredentials({ "pin" }, { visibility = { displayed = false } })))
end

test.set_test_init_function(test_init)

test.register_message_test(
  "Battery percentage report should be handled",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = {
        mock_device.id,
        PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device, 55)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.battery.battery(55))
    }
  },
  {
     min_api_version = 14
  }
)

local mock_device_yrd = test.mock_device.build_test_zigbee_device({
  profile = t_utils.get_profile_definition("base-lock.yml"),
  zigbee_endpoints ={
    [1] = {
      id = 1,
      manufacturer ="Yale",
      model ="YRD220/240 TSDB",
      server_clusters = {}
    }
  }
})

local function test_init_yrd()
  test.mock_device.add_test_device(mock_device_yrd)
  mock_device_yrd:set_field(consts.DRIVER_STATE.SLGA_MIGRATED, true, { persist = true })
  -- init emits migrated state for SLGA-migrated devices
  test.socket.capability:__expect_send(mock_device_yrd:generate_test_message("main", capabilities.lockCodes.migrated(true, { visibility = { displayed = false } })))
  test.socket.capability:__expect_send(mock_device_yrd:generate_test_message("main", capabilities.lockCredentials.supportedCredentials({ "pin" }, { visibility = { displayed = false } })))
end

test.register_message_test(
    "Battery percentage report should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = {
          mock_device_yrd.id,
          PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device_yrd, 55) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device_yrd:generate_test_message("main", capabilities.battery.battery(55))
      }
    },
    {
      test_init = test_init_yrd,
      min_api_version = 14
    }
)

test.run_registered_tests()
