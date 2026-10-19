-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- A button whose state is in the discovery cache is added and initialized without any REST
--- requests (no address is registered, so any connection attempt would fail the test).

local test = require "integration_test"
local hue_test_helpers = require "test.hue_test_helpers"
local Fields = require "fields"

-- Use proper UUID format for Hue resource IDs
local BUTTON_RID = "aaaaaaaa-bbbb-cccc-dddd-111111111111"
local BUTTON_DEVICE_ID = "aaaaaaaa-bbbb-cccc-dddd-222222222222"
local POWER_RID = "aaaaaaaa-bbbb-cccc-dddd-333333333333"

-- Single button device fixture WITHOUT SSE (lifecycle only)
local fixtures = hue_test_helpers.HueDeviceBuilder.new()
  :with_bridge()
  :with_button(BUTTON_RID, {
    battery = 85,
    device_id = BUTTON_DEVICE_ID,
    power_rid = POWER_RID,
  })
  :start()

local mock_button = fixtures.devices[1]

test.set_test_init_function(fixtures.test_init)

test.register_coroutine_test(
  "a cached button is added and initialized from its discovery state",
  function()
    test.wait_for_events()
    local button = fixtures.driver_device(mock_button)
    assert(button:get_field(Fields._ADDED) == true, "expected the button to have been added")
    assert(button:get_field(Fields.DEVICE_TYPE) == "button", "expected the button's device type")
    assert(button:get_field(Fields.HUE_DEVICE_ID) == BUTTON_DEVICE_ID, "expected the button's Hue device id")
  end
)

test.run_registered_tests()
