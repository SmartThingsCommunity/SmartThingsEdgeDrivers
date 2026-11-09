-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- A Hue Bridge Pro keeps the Hue resource IDs of the devices migrated to it from an older bridge,
--- and there is no way to migrate the SmartThings records along with them, so a user who adds the
--- new bridge ends up with two records for each device: the old bridge's and the new one's, with
--- the same resource ID. After a driver restart (nothing cached yet), the old bridge's records, whose
--- bridge is gone, are queued as strays. A stray is only resolved by its own bridge, so the new bridge
--- never adopts them (which would take over the new records' registrations) or rescans for them;
--- they stay queued, in case their own bridge comes back. Covered for each type of child device:
--- button, light, motion sensor and contact sensor.

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

-- The devices on the new bridge (the Bridge Pro), each with its Hue device ID and services.
local devices = {
  button = {
    label = "Hue Smart Button", profile = "single-button.yml", model_id = "ROM001", id_v1 = "/sensors/7",
    rid = "77777777-7777-7777-7777-000000000001",
    device_id = "77777777-7777-7777-7777-000000000002",
    services = {
      { rtype = "zigbee_connectivity", rid = "77777777-7777-7777-7777-000000000004" },
      { rtype = "device_power", rid = "77777777-7777-7777-7777-000000000003" },
      { rtype = "button", rid = "77777777-7777-7777-7777-000000000001" },
    },
  },
  light = {
    label = "Hue Light", profile = "white-and-color-ambiance.yml", model_id = "LCA001", id_v1 = "/lights/7",
    rid = "77777777-7777-7777-7777-000000000011",
    device_id = "77777777-7777-7777-7777-000000000012",
    services = {
      { rtype = "zigbee_connectivity", rid = "77777777-7777-7777-7777-000000000014" },
      { rtype = "light", rid = "77777777-7777-7777-7777-000000000011" },
    },
  },
  motion = {
    label = "Hue Motion Sensor", profile = "motion-sensor.yml", model_id = "SML001", id_v1 = "/sensors/8",
    rid = "77777777-7777-7777-7777-000000000021",
    device_id = "77777777-7777-7777-7777-000000000022",
    services = {
      { rtype = "zigbee_connectivity", rid = "77777777-7777-7777-7777-000000000024" },
      { rtype = "device_power", rid = "77777777-7777-7777-7777-000000000023" },
      { rtype = "motion", rid = "77777777-7777-7777-7777-000000000021" },
      { rtype = "temperature", rid = "77777777-7777-7777-7777-000000000025" },
      { rtype = "light_level", rid = "77777777-7777-7777-7777-000000000026" },
    },
  },
  contact = {
    label = "Hue Contact Sensor", profile = "contact-sensor.yml", model_id = "SOC001", id_v1 = "/sensors/9",
    rid = "77777777-7777-7777-7777-000000000031",
    device_id = "77777777-7777-7777-7777-000000000032",
    services = {
      { rtype = "zigbee_connectivity", rid = "77777777-7777-7777-7777-000000000034" },
      { rtype = "device_power", rid = "77777777-7777-7777-7777-000000000033" },
      { rtype = "contact", rid = "77777777-7777-7777-7777-000000000031" },
      { rtype = "tamper", rid = "77777777-7777-7777-7777-000000000035" },
    },
  },
}
local DEVICE_TYPES = { "button", "light", "motion", "contact" }

local function service_rid(device, rtype)
  for _, svc in ipairs(device.services) do
    if svc.rtype == rtype then return svc.rid end
  end
end

-- The new bridge.
local fixtures = hue_test_helpers.HueDeviceBuilder.new()
  :with_bridge()
  :start()
local mock_bridge = fixtures.bridge

-- The old bridge, no longer on the network.
local mock_old_bridge = test.mock_device.build_test_lan_device({
  label = "Old Hue Bridge",
  profile = t_utils.get_profile_definition("hue-bridge.yml"),
  device_network_id = "001788AABBCC",
})

-- For each device, the new bridge's record (onboarded in an earlier run of the driver) and the old
-- bridge's record for the same resource.
for _, device_type in ipairs(DEVICE_TYPES) do
  local device = devices[device_type]
  device.mock = test.mock_device.build_test_lan_device({
    label = device.label,
    profile = t_utils.get_profile_definition(device.profile),
    parent_assigned_child_key = device_type .. ":" .. device.rid,
    parent_device_id = mock_bridge.id,
  })
  device.old_mock = test.mock_device.build_test_lan_device({
    label = device.label .. " (old bridge)",
    profile = t_utils.get_profile_definition(device.profile),
    parent_assigned_child_key = device_type .. ":" .. device.rid,
    parent_device_id = mock_old_bridge.id,
  })
end

local scenario, conns = hue_test_helpers.create_hue_scenario()
local rest = conns.rest
hue_test_helpers.setup_sse_expectations(conns.sse, rest)

-- The devices' resources, for the new records' init and refresh (and a stray resolver's scan,
-- were one to run).
local device_listing = {}
for _, device_type in ipairs(DEVICE_TYPES) do
  local device = devices[device_type]
  device.hue_device = {
    type = "device",
    id = device.device_id,
    id_v1 = device.id_v1,
    metadata = { name = device.label },
    product_data = { manufacturer_name = "Signify Netherlands B.V.", model_id = device.model_id, product_name = device.label },
    services = device.services,
  }
  table.insert(device_listing, device.hue_device)
  http.expect_request(rest, "GET", "/clip/v2/resource/device/" .. device.device_id, {
    body = { errors = {}, data = { device.hue_device } },
    reusable = true,
  })
  hue_test_helpers.expect_zigbee_connectivity(rest, service_rid(device, "zigbee_connectivity"), device.device_id,
    { reusable = true })
end
http.expect_request(rest, "GET", "/clip/v2/resource/device", {
  body = { errors = {}, data = device_listing },
  reusable = true,
})

local function owner(device) return { rid = device.device_id, rtype = "device" } end
local function expect_resource(device, rtype, data)
  data.owner = owner(device)
  hue_test_helpers.expect_resource(rest, rtype, service_rid(device, rtype), data, { reusable = true })
end
expect_resource(devices.button, "button", {
  metadata = { control_id = 1 },
  button = {
    button_report = { event = "initial_press", updated = "2024-01-01T00:00:00Z" },
    event_values = { "short_release", "long_press", "long_release" },
  },
})
expect_resource(devices.button, "device_power", { power_state = { battery_level = 85, battery_state = "normal" } })
http.expect_request(rest, "GET", "/clip/v2/resource/light/" .. devices.light.rid, {
  body = hue_test_helpers.light_resource({
    rid = devices.light.rid, device_id = devices.light.device_id, label = devices.light.label,
    on = { on = true }, dimming = { brightness = 100 }, mode = "normal",
  }),
  reusable = true,
})
expect_resource(devices.motion, "motion", { enabled = true, motion = { motion = false, motion_valid = true } })
expect_resource(devices.motion, "temperature", { enabled = true, temperature = { temperature = 20.0, temperature_valid = true } })
expect_resource(devices.motion, "light_level", { enabled = true, light = { light_level = 30000, light_level_valid = true } })
expect_resource(devices.motion, "device_power", { power_state = { battery_level = 80, battery_state = "normal" } })
expect_resource(devices.contact, "contact", { enabled = true, contact_report = { state = "contact" } })
expect_resource(devices.contact, "tamper", { tamper_reports = { { state = "not_tampered" } } })
expect_resource(devices.contact, "device_power", { power_state = { battery_level = 75, battery_state = "normal" } })

-- The fields the earlier run persisted (see test_hue_driver_restart.lua for why they're seeded).
local function seed_persisted_fields()
  for _, device_type in ipairs(DEVICE_TYPES) do
    local device = devices[device_type]
    device.mock:set_field(Fields._ADDED, true, { persist = true })
    device.mock:set_field(Fields.DEVICE_TYPE, device_type, { persist = true })
    device.mock:set_field(Fields.RESOURCE_ID, device.rid, { persist = true })
    device.mock:set_field(Fields.HUE_DEVICE_ID, device.device_id, { persist = true })
    device.mock:set_field(Fields.PARENT_DEVICE_ID, mock_bridge.id, { persist = true })
    device.mock:set_field(Fields._REFRESH_AFTER_INIT, false, { persist = true })
  end
  if devices.button.mock then
    devices.button.mock:set_field(Fields.BUTTON_INDEX_MAP, { [devices.button.rid] = 1 }, { persist = true })
  end
  if devices.light.mock then
    devices.light.mock:set_field(Fields.MIN_KELVIN, 2000, { persist = true })
    devices.light.mock:set_field(Fields.MAX_KELVIN, 6500, { persist = true })
  end
  -- The old bridge isn't on the network in this run, so its init waits to find it.
  mock_old_bridge:set_field(Fields._ADDED, true, { persist = true })
  mock_old_bridge:set_field(Fields.DEVICE_TYPE, HueDeviceTypes.BRIDGE, { persist = true })
  mock_old_bridge:set_field(Fields.BRIDGE_ID, mock_old_bridge.device_network_id, { persist = true })
  mock_old_bridge:set_field(Fields.IPV4, "192.168.1.99", { persist = true })
  mock_old_bridge:set_field(HueApi.APPLICATION_KEY_HEADER, "old-bridge-api-key", { persist = true })
end

hue_test_helpers.setup_scenario_test_init(function()
  fixtures.test_init()
  test.mock_device.add_test_device(mock_old_bridge)
  for _, device_type in ipairs(DEVICE_TYPES) do
    test.mock_device.add_test_device(devices[device_type].mock)
    test.mock_device.add_test_device(devices[device_type].old_mock)
  end
  seed_persisted_fields()
  test.socket.capability:__set_channel_ordering("relaxed")
  -- Both lights' `init` runs (a light's init copes with a deferred `added`), and emits levelRange
  -- whether or not the light was onboarded. Nothing else is expected from the old records: they
  -- would only emit (supported button values, a refresh's state) if they were wrongly adopted.
  hue_test_helpers.expect_light_init_events(devices.light.mock, devices.light.profile)
  hue_test_helpers.expect_light_init_events(devices.light.old_mock, devices.light.profile)
end, scenario)

local function device_scans()
  return http.count_requests(rest, "GET", "/clip/v2/resource/device")
end

test.register_coroutine_test(
  "an old bridge's strays are not adopted by the new bridge, nor is the new bridge scanned for them",
  function()
    hue_test_helpers.wait_for_init(scenario, mock_bridge)
    -- Long enough for the stray resolver's periodic retry (every 30s) to have run several times.
    test.let_time_pass(120)
    test.wait_for_events()

    local driver = fixtures.driver_device(mock_bridge).driver
    local by_rid = driver.hue_identifier_to_device_record_by_bridge[hue_test_helpers.BRIDGE_DNI] or {}
    for _, device_type in ipairs(DEVICE_TYPES) do
      local device = devices[device_type]
      local old = fixtures.driver_device(device.old_mock)
      assert(old:get_field(Fields._ADDED) == nil,
        string.format("expected the old bridge's %s not to be adopted", device_type))
      assert(old:get_field(Fields.HUE_DEVICE_ID) == nil and old:get_field(Fields.DEVICE_TYPE) == nil,
        string.format("expected no Hue device fields on the old bridge's %s", device_type))
      assert(not test.mock_devices_api.__is_device_deleted(device.old_mock.id),
        string.format("expected the old bridge's %s not to be deleted", device_type))

      -- The new bridge's record keeps the resource's registration and its fields.
      local new = fixtures.driver_device(device.mock)
      assert(by_rid[device.rid] ~= nil and by_rid[device.rid].id == device.mock.id,
        string.format("expected the %s's resource to stay registered to the new bridge's record", device_type))
      assert(new:get_field(Fields.HUE_DEVICE_ID) == device.device_id,
        string.format("expected the new bridge's %s to keep its Hue device ID", device_type))
      assert(not test.mock_devices_api.__is_device_deleted(device.mock.id),
        string.format("expected the new bridge's %s not to be deleted", device_type))
    end

    -- The strays aren't the new bridge's, so the new bridge is never scanned for them.
    assert(device_scans() == 0, string.format(
      "expected the new bridge not to be scanned for another bridge's strays, got %d scans", device_scans()))
  end,
  { min_api_version = 23 }
)

test.run_registered_tests()
