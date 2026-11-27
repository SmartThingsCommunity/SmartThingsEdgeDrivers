-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- A light migrated from the DTH integration (no parent, no Hue resource ID, only the v1 light ID
--- and API key the DTH stored) is deliberately not migrated.
---
--- `migrate_device` reads its options with `select(-1, ...)`, which raises when the lifecycle
--- event passes no extra arguments, so a DTH device's `added` stops there. Making that not raise
--- (2533e079) let devices go on into a crash in the migration handlers, and was reverted
--- (d2e65b29). Until migration is fixed and tested end to end, the DTH light must stay as it is:
--- not added, not queued as a stray, and not looked for on the bridge.

-- These tests use the integration test framework's LAN support, new in lua_libs API version 23.
-- With older lua_libs, skip the file rather than fail loading it.
if require("version").api < 23 then return end

local test = require "integration_test"
local t_utils = require "integration_test.utils"
local hue_test_helpers = require "test.hue_test_helpers"
local http = require "integration_test.connection_scenario_http"
local Fields = require "fields"

local LIGHT_V1_ID = "5"

local fixtures = hue_test_helpers.HueDeviceBuilder.new()
  :with_bridge()
  :start()

local mock_bridge = fixtures.bridge

-- As the DTH integration left it: no parent, a parent-assigned key of `<bridge ID>/<v1 ID>`, and
-- the v1 ID and API key in its data.
local mock_light = test.mock_device.build_test_lan_device({
  label = "Migrated Hue Light",
  profile = t_utils.get_profile_definition("white-and-color-ambiance.yml"),
  parent_assigned_child_key = hue_test_helpers.BRIDGE_DNI .. "/" .. LIGHT_V1_ID,
  data = { bulbId = LIGHT_V1_ID, username = hue_test_helpers.API_KEY },
})

local scenario, conns = hue_test_helpers.create_hue_scenario()
local rest = conns.rest
hue_test_helpers.setup_sse_expectations(conns.sse, rest)

hue_test_helpers.setup_scenario_test_init(function()
  fixtures.test_init()
  test.mock_device.add_test_device(mock_light)
  -- The light's `added` stops at `migrate_device`'s `select` (see above), which the lifecycle
  -- handler wrapper catches and logs. Any other caught error still fails the test.
  test.allow_caught_error("lifecycle_handlers/init%.lua:%d+: bad argument #1 to 'select' %(index out of range%)")
  -- Nothing is expected from the light: a capability event or metadata update from it, or a
  -- request to the bridge on its behalf, would fail the test.
end, scenario)

test.register_coroutine_test(
  "a light migrated from the DTH integration is left unmigrated",
  function()
    hue_test_helpers.wait_for_init(scenario, mock_bridge)
    -- Long enough for the stray resolver to have rescanned the bridge, had the light been queued.
    test.let_time_pass(90)
    test.wait_for_events()

    local light = fixtures.driver_device(mock_light)
    assert(light:get_field(Fields._ADDED) == nil, "expected the DTH light not to have been added")
    assert(light:get_field(Fields.RESOURCE_ID) == nil, "expected no resource ID on the DTH light")
    assert(light:get_field(Fields.RETRY_MIGRATION) == nil, "expected the DTH light not to be queued for migration")
    assert(http.count_requests(rest, "GET", "/clip/v2/resource/device") == 0,
      "expected no scan of the bridge for the DTH light")
    assert(not test.mock_devices_api.__is_device_deleted(mock_light.id), "expected the DTH light not to be deleted")
  end,
  { min_api_version = 23 }
)

test.run_registered_tests()
