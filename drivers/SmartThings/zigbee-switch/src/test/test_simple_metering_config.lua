-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"
local zigbee_constants = require "st.zigbee.constants"

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("switch-power-energy.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "LEDVANCE",
        model = "PLUG COMPACT EU EM T",
        server_clusters = { 0x0006, 0x0702 }
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
  "Device init should set default multiplier and divisor only when not already set",
  function()
    assert(mock_device:get_field(zigbee_constants.SIMPLE_METERING_MULTIPLIER_KEY) == nil)
    assert(mock_device:get_field(zigbee_constants.SIMPLE_METERING_DIVISOR_KEY) == nil)
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })
    test.wait_for_events()
    assert(mock_device:get_field(zigbee_constants.SIMPLE_METERING_MULTIPLIER_KEY) == 1)
    assert(mock_device:get_field(zigbee_constants.SIMPLE_METERING_DIVISOR_KEY) == 100)
  end
)

test.register_coroutine_test(
  "Device init should preserve device-reported multiplier and divisor",
  function()
    mock_device:set_field(zigbee_constants.SIMPLE_METERING_MULTIPLIER_KEY, 5, {persist = true})
    mock_device:set_field(zigbee_constants.SIMPLE_METERING_DIVISOR_KEY, 1000, {persist = true})
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })
    test.wait_for_events()
    assert(mock_device:get_field(zigbee_constants.SIMPLE_METERING_MULTIPLIER_KEY) == 5)
    assert(mock_device:get_field(zigbee_constants.SIMPLE_METERING_DIVISOR_KEY) == 1000)
  end
)

test.run_registered_tests()
