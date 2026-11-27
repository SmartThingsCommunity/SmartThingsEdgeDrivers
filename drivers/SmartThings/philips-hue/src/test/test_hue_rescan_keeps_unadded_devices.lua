-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- When the bridge's event stream connects outside of discovery, the driver rescans the bridge and
--- deletes the child devices the bridge no longer has. It compares them by their Hue device ID, so a
--- child that hasn't been added yet (a stray, waiting for its state) has nothing to compare and must
--- be left alone, whereas an onboarded child the bridge doesn't report is deleted.

-- These tests use the integration test framework's LAN support, new in lua_libs API version 23.
-- With older lua_libs, skip the file rather than fail loading it.
if require("version").api < 23 then return end

local test = require "integration_test"
local t_utils = require "integration_test.utils"
local hue_test_helpers = require "test.hue_test_helpers"
local http = require "integration_test.connection_scenario_http"
local Fields = require "fields"

local LIGHT_RID = "66666666-6666-6666-6666-000000000001"
local STRAY_BUTTON_RID = "66666666-6666-6666-6666-000000000002"

local fixtures = hue_test_helpers.HueDeviceBuilder.new()
  :with_bridge()
  :with_light(LIGHT_RID, { on = { on = true } }, "white-and-color-ambiance.yml")
  :expect_light_init_refreshes()
  :start()

local mock_bridge, mock_light = fixtures.bridge, fixtures.devices[1]

-- Not in the discovery cache, so it is queued as a stray and never gets a Hue device ID.
local mock_stray_button = test.mock_device.build_test_lan_device({
  label = "Hue Smart Button",
  profile = t_utils.get_profile_definition("single-button.yml"),
  parent_assigned_child_key = "button:" .. STRAY_BUTTON_RID,
  parent_device_id = mock_bridge.id,
})

-- Discovery isn't running, so the event stream connecting starts the rescan (which deletes).
-- Registered after the fixture's own setup, so it takes precedence.
test.add_test_env_setup_func(function()
  require("disco").discovery_active = false
end)

local scenario, conns = hue_test_helpers.create_hue_scenario()
local rest = conns.rest
hue_test_helpers.setup_light_init_expectations(rest, fixtures.configs.light[1])
hue_test_helpers.setup_sse_expectations(conns.sse, rest)
-- The bridge no longer has any devices: neither the light nor the button.
http.expect_request(rest, "GET", "/clip/v2/resource/device", {
  body = { errors = {}, data = {} },
  reusable = true,
})

hue_test_helpers.setup_scenario_test_init(function()
  fixtures.test_init()
  test.mock_device.add_test_device(mock_stray_button)
  test.socket.capability:__set_channel_ordering("relaxed")
end, scenario)

test.register_coroutine_test(
  "a rescan deletes an onboarded device the bridge no longer has, but not one that hasn't been added",
  function()
    hue_test_helpers.wait_for_init(scenario, mock_bridge)
    test.wait_until(function()
      return http.count_requests(rest, "GET", "/clip/v2/resource/device") >= 1
    end, { within = 30, message = "the bridge being rescanned" })
    test.wait_for_events()

    -- The rescan did delete: the onboarded light isn't on the bridge any more.
    assert(test.mock_devices_api.__is_device_deleted(mock_light.id),
      "expected the onboarded light the bridge no longer has to be deleted")

    local stray = fixtures.driver_device(mock_stray_button)
    assert(stray:get_field(Fields.HUE_DEVICE_ID) == nil, "expected the stray button to have no Hue device ID")
    assert(not test.mock_devices_api.__is_device_deleted(mock_stray_button.id),
      "expected the stray button not to be deleted for lacking a Hue device ID")
  end,
  { min_api_version = 23 }
)

test.run_registered_tests()
