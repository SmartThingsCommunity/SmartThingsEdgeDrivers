-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- A child device whose resource state isn't in the discovery cache is treated as a "stray":
--- it isn't onboarded (no REST state fetch, no device fields set) until the bridge reports it.
--- Here the bridge, scanned for it once the bridge initializes, doesn't have it.

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
  :expect_light_init_refreshes()
  :start()

local mock_bridge, mock_cached_light = fixtures.bridge, fixtures.devices[1]

local mock_new_light = test.mock_device.build_test_lan_device({
  label = "New Hue Light",
  profile = t_utils.get_profile_definition("white-and-color-ambiance.yml"),
  parent_assigned_child_key = "light:" .. NEW_LIGHT_RID,
  parent_device_id = mock_bridge.id,
})

local scenario, conns = hue_test_helpers.create_hue_scenario()
hue_test_helpers.setup_light_init_expectations(conns.rest, fixtures.configs.light[1])
hue_test_helpers.setup_sse_expectations(conns.sse, conns.rest)
-- With a stray waiting, the bridge initializing has the driver scan the bridge's devices for it.
-- The bridge only has the cached light.
local cached_light = fixtures.configs.light[1]
http.expect_request(conns.rest, "GET", "/clip/v2/resource/device", {
  body = { errors = {}, data = { {
    type = "device",
    id = cached_light.device_id,
    id_v1 = "/lights/1",
    metadata = { name = cached_light.label, archetype = "sultan_bulb" },
    product_data = { manufacturer_name = "Signify Netherlands B.V.", model_id = "TEST", product_name = cached_light.label },
    services = {
      { rtype = "light", rid = cached_light.rid },
      { rtype = "zigbee_connectivity", rid = cached_light.zigbee_rid },
    },
  } } },
  reusable = true,
})

hue_test_helpers.setup_scenario_test_init(function()
  fixtures.test_init()
  test.mock_device.add_test_device(mock_new_light)
  -- The stray light initializes while the cached light's refreshes wait on the bridge, so the
  -- two lights' events interleave; only each light's own events are in a fixed order.
  test.socket.capability:__set_channel_ordering("relaxed")
  -- Light init emits levelRange whether or not the light was onboarded.
  hue_test_helpers.expect_light_init_events(mock_new_light, "white-and-color-ambiance.yml")
end, scenario)

test.register_coroutine_test(
  "a child device with no cached resource state is left as a stray, not onboarded",
  function()
    hue_test_helpers.wait_for_init(scenario, mock_bridge)

    local stray = fixtures.driver_device(mock_new_light)
    assert(stray:get_field(Fields._ADDED) == nil, "expected the stray light not to have been added")
    assert(stray:get_field(Fields.HUE_DEVICE_ID) == nil and stray:get_field(Fields.DEVICE_TYPE) == nil,
      "expected no Hue device fields on the stray light")
    assert(http.count_requests(conns.rest, "GET", "/clip/v2/resource/device") >= 1,
      "expected the driver to look for the stray light on the bridge once the bridge initialized")
    assert(http.count_requests(conns.rest, "GET", "/clip/v2/resource/light/" .. NEW_LIGHT_RID) == 0,
      "expected no state request for the stray light")

    local cached = fixtures.driver_device(mock_cached_light)
    assert(cached:get_field(Fields._ADDED) == true and cached:get_field(Fields.DEVICE_TYPE) == "light",
      "expected the cached light to have been onboarded")
  end
)

test.run_registered_tests()
