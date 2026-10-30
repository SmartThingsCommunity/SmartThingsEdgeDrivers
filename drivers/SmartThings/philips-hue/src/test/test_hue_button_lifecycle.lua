-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- A button whose state is in the discovery cache is added and initialized from it, then
--- refreshed from the bridge once the bridge has initialized.

local test = require "integration_test"
local hue_test_helpers = require "test.hue_test_helpers"
local Fields = require "fields"

-- Use proper UUID format for Hue resource IDs
local BUTTON_RID = "aaaaaaaa-bbbb-cccc-dddd-111111111111"
local BUTTON_DEVICE_ID = "aaaaaaaa-bbbb-cccc-dddd-222222222222"
local POWER_RID = "aaaaaaaa-bbbb-cccc-dddd-333333333333"

local fixtures = hue_test_helpers.HueDeviceBuilder.new()
  :with_bridge()
  :with_button(BUTTON_RID, {
    battery = 85,
    device_id = BUTTON_DEVICE_ID,
    power_rid = POWER_RID,
  })
  :start()

local mock_bridge, mock_button = fixtures.bridge, fixtures.devices[1]

local scenario, conns = hue_test_helpers.create_hue_scenario()
hue_test_helpers.setup_button_init_expectations(conns.rest, conns.sse, fixtures.configs.button[1])
hue_test_helpers.setup_scenario_test_init(fixtures.test_init, scenario)

test.register_coroutine_test(
  "a cached button is added and initialized from its discovery state",
  function()
    hue_test_helpers.wait_for_init(scenario, mock_bridge)
    local button = fixtures.driver_device(mock_button)
    assert(button:get_field(Fields._ADDED) == true, "expected the button to have been added")
    assert(button:get_field(Fields.DEVICE_TYPE) == "button", "expected the button's device type")
    assert(button:get_field(Fields.HUE_DEVICE_ID) == BUTTON_DEVICE_ID, "expected the button's Hue device id")
  end
)

test.run_registered_tests()
