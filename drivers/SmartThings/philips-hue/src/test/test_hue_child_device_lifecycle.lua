-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- A child device whose resource state isn't in the discovery cache is treated as a "stray":
--- it isn't onboarded (no REST state fetch, no device fields set) until the bridge reports it.

local test = require "integration_test"
local t_utils = require "integration_test.utils"
local hue_test_helpers = require "test.hue_test_helpers"
local http = require "integration_test.connection_scenario_http"
local Fields = require "fields"

-- A light that is in the discovery cache, alongside the device under test, which isn't.
local CACHED_LIGHT_RID = "33333333-3333-3333-3333-333333333333"
local NEW_LIGHT_RID = "44444444-4444-4444-4444-444444444444"

local fixtures = hue_test_helpers.HueDeviceBuilder.new()
  :with_bridge()
  :with_light(CACHED_LIGHT_RID, { on = { on = true } }, "white-and-color-ambiance.yml")
  :start()

local mock_bridge, mock_cached_light = fixtures.bridge, fixtures.devices[1]

local mock_new_light = test.mock_device.build_test_lan_device({
  label = "New Hue Light",
  profile = t_utils.get_profile_definition("white-and-color-ambiance.yml"),
  parent_assigned_child_key = "light:" .. NEW_LIGHT_RID,
  parent_device_id = mock_bridge.id,
})

local scenario, conns = hue_test_helpers.create_hue_scenario()

hue_test_helpers.setup_scenario_test_init(function()
  fixtures.test_init()
  test.mock_device.add_test_device(mock_new_light)
  -- Light init emits levelRange whether or not the light was onboarded.
  hue_test_helpers.expect_light_init_events(mock_new_light)
end, scenario)

test.register_coroutine_test(
  "a child device with no cached resource state is left as a stray, not onboarded",
  function()
    test.wait_for_events()

    local stray = fixtures.driver_device(mock_new_light)
    assert(stray:get_field(Fields._ADDED) == nil, "expected the stray light not to have been added")
    assert(stray:get_field(Fields.HUE_DEVICE_ID) == nil and stray:get_field(Fields.DEVICE_TYPE) == nil,
      "expected no Hue device fields on the stray light")
    assert(http.count_requests(conns.rest, "GET", "/clip/v2/resource/light/" .. NEW_LIGHT_RID) == 0,
      "expected no state request for the stray light")

    local cached = fixtures.driver_device(mock_cached_light)
    assert(cached:get_field(Fields._ADDED) == true and cached:get_field(Fields.DEVICE_TYPE) == "light",
      "expected the cached light to have been onboarded")
  end
)

test.run_registered_tests()
