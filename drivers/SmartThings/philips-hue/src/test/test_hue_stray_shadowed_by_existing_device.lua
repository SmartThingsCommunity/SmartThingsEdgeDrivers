-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- A Hue Bridge Pro keeps the Hue resource IDs of the devices migrated to it from an older bridge,
--- and there is no way to migrate the SmartThings records along with them, so a user who adds the
--- new bridge ends up with two records for each device: the old bridge's and the new one's, with
--- the same resource ID. After a driver restart (nothing cached yet), the old bridge's record, whose
--- bridge is gone, is queued as a stray. A stray is only resolved by its own bridge, so the new bridge
--- never adopts it (which would take over the new record's registration) or rescans for it; it stays
--- queued, in case its own bridge comes back.

-- These tests use the integration test framework's LAN support, new in lua_libs API version 23.
-- With older lua_libs, skip the file rather than fail loading it.
if require("version").api < 23 then return end

local test = require "integration_test"
local t_utils = require "integration_test.utils"
local hue_test_helpers = require "test.hue_test_helpers"
local http = require "integration_test.connection_scenario_http"
local Fields = require "fields"
local HueApi = require "hue.api"
local HueDeviceTypes = require "hue_device_types"

local BUTTON_RID = "77777777-7777-7777-7777-000000000001"
local BUTTON_DEVICE_ID = "77777777-7777-7777-7777-000000000002"
local POWER_RID = "77777777-7777-7777-7777-000000000003"
local ZIGBEE_RID = "77777777-7777-7777-7777-000000000004"
local BUTTON_LABEL = "Hue Smart Button"

-- The new bridge (the Bridge Pro).
local fixtures = hue_test_helpers.HueDeviceBuilder.new()
  :with_bridge()
  :start()
local mock_bridge = fixtures.bridge

-- The new bridge's record for the button, onboarded in an earlier run of the driver.
local mock_button = test.mock_device.build_test_lan_device({
  label = BUTTON_LABEL,
  profile = t_utils.get_profile_definition("single-button.yml"),
  parent_assigned_child_key = "button:" .. BUTTON_RID,
  parent_device_id = mock_bridge.id,
})

-- The old bridge, no longer on the network, and its record for the same button.
local mock_old_bridge = test.mock_device.build_test_lan_device({
  label = "Old Hue Bridge",
  profile = t_utils.get_profile_definition("hue-bridge.yml"),
  device_network_id = "001788AABBCC",
})
local mock_old_button = test.mock_device.build_test_lan_device({
  label = BUTTON_LABEL .. " (old bridge)",
  profile = t_utils.get_profile_definition("single-button.yml"),
  parent_assigned_child_key = "button:" .. BUTTON_RID,
  parent_device_id = mock_old_bridge.id,
})

local scenario, conns = hue_test_helpers.create_hue_scenario()
local rest = conns.rest
hue_test_helpers.setup_sse_expectations(conns.sse, rest)

-- The button's resources, for the new record's init and refresh and the stray resolver's scan.
local button_device = {
  type = "device",
  id = BUTTON_DEVICE_ID,
  id_v1 = "/sensors/7",
  metadata = { name = BUTTON_LABEL },
  product_data = { manufacturer_name = "Signify Netherlands B.V.", model_id = "ROM001", product_name = BUTTON_LABEL },
  services = {
    { rtype = "zigbee_connectivity", rid = ZIGBEE_RID },
    { rtype = "device_power", rid = POWER_RID },
    { rtype = "button", rid = BUTTON_RID },
  },
}
http.expect_request(rest, "GET", "/clip/v2/resource/device", {
  body = { errors = {}, data = { button_device } },
  reusable = true,
})
http.expect_request(rest, "GET", "/clip/v2/resource/device/" .. BUTTON_DEVICE_ID, {
  body = { errors = {}, data = { button_device } },
  reusable = true,
})
hue_test_helpers.expect_zigbee_connectivity(rest, ZIGBEE_RID, BUTTON_DEVICE_ID, { reusable = true })
hue_test_helpers.expect_resource(rest, "button", BUTTON_RID, {
  owner = { rid = BUTTON_DEVICE_ID, rtype = "device" },
  metadata = { control_id = 1 },
  button = {
    button_report = { event = "initial_press", updated = "2024-01-01T00:00:00Z" },
    event_values = { "short_release", "long_press", "long_release" },
  },
}, { reusable = true })
hue_test_helpers.expect_resource(rest, "device_power", POWER_RID, {
  owner = { rid = BUTTON_DEVICE_ID, rtype = "device" },
  power_state = { battery_level = 85, battery_state = "normal" },
}, { reusable = true })

-- The fields the earlier run persisted (see test_hue_driver_restart.lua for why they're seeded).
local function seed_persisted_fields()
  mock_button:set_field(Fields._ADDED, true, { persist = true })
  mock_button:set_field(Fields.DEVICE_TYPE, HueDeviceTypes.BUTTON, { persist = true })
  mock_button:set_field(Fields.RESOURCE_ID, BUTTON_RID, { persist = true })
  mock_button:set_field(Fields.HUE_DEVICE_ID, BUTTON_DEVICE_ID, { persist = true })
  mock_button:set_field(Fields.PARENT_DEVICE_ID, mock_bridge.id, { persist = true })
  mock_button:set_field(Fields.BUTTON_INDEX_MAP, { [BUTTON_RID] = 1 }, { persist = true })
  mock_button:set_field(Fields._REFRESH_AFTER_INIT, false, { persist = true })
  -- The old bridge isn't on the network in this run, so its init waits to find it.
  mock_old_bridge:set_field(Fields._ADDED, true, { persist = true })
  mock_old_bridge:set_field(Fields.DEVICE_TYPE, HueDeviceTypes.BRIDGE, { persist = true })
  mock_old_bridge:set_field(Fields.BRIDGE_ID, mock_old_bridge.device_network_id, { persist = true })
  mock_old_bridge:set_field(Fields.IPV4, "192.168.1.99", { persist = true })
  mock_old_bridge:set_field(HueApi.APPLICATION_KEY_HEADER, "old-bridge-api-key", { persist = true })
end

hue_test_helpers.setup_scenario_test_init(function()
  fixtures.test_init()
  for _, mock in ipairs({ mock_button, mock_old_bridge, mock_old_button }) do
    test.mock_device.add_test_device(mock)
  end
  seed_persisted_fields()
  -- No capability events are expected: the new record was set up in the earlier run, and the old
  -- one would only emit (its supported button values) if it were wrongly adopted.
end, scenario)

local function device_scans()
  return http.count_requests(rest, "GET", "/clip/v2/resource/device")
end

test.register_coroutine_test(
  "an old bridge's stray is not adopted by the new bridge, nor is the new bridge scanned for it",
  function()
    hue_test_helpers.wait_for_init(scenario, mock_bridge)
    -- Long enough for the stray resolver's periodic retry (every 30s) to have run several times.
    test.let_time_pass(120)
    test.wait_for_events()

    local old_button = fixtures.driver_device(mock_old_button)
    assert(old_button:get_field(Fields._ADDED) == nil, "expected the old bridge's button not to be adopted")
    assert(old_button:get_field(Fields.HUE_DEVICE_ID) == nil,
      "expected no Hue device fields on the old bridge's button")
    assert(not test.mock_devices_api.__is_device_deleted(mock_old_button.id),
      "expected the old bridge's button not to be deleted")

    -- The new bridge's record keeps the button's registration.
    local new_button = fixtures.driver_device(mock_button)
    local by_rid = new_button.driver.hue_identifier_to_device_record_by_bridge[hue_test_helpers.BRIDGE_DNI] or {}
    assert(by_rid[BUTTON_RID] ~= nil and by_rid[BUTTON_RID].id == mock_button.id,
      "expected the button's resource to stay registered to the new bridge's record")
    assert(new_button:get_field(Fields.HUE_DEVICE_ID) == BUTTON_DEVICE_ID,
      "expected the new bridge's button to keep its Hue device ID")

    -- The stray isn't the new bridge's, so the new bridge is never scanned for it.
    assert(device_scans() == 0, string.format(
      "expected the new bridge not to be scanned for another bridge's stray, got %d scans", device_scans()))
  end,
  { min_api_version = 23 }
)

test.run_registered_tests()
