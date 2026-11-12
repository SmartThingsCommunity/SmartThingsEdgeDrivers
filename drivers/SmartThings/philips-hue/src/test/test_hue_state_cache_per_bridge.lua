-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- The driver caches device state per bridge. A Hue Bridge Pro keeps the resource IDs of the devices
--- migrated to it, so the new bridge's state for a device has the same resource ID as the old
--- bridge's record for it. With the new bridge's state cached (as right after discovery), the old
--- bridge's records must not be set up from it: they only see their own bridge's state, and since
--- that bridge is gone, they are queued as strays, while the new bridge's records are onboarded as
--- usual. Covered for each type of child device: button, light, motion sensor and contact sensor.

-- These tests use the integration test framework's LAN support, new in lua_libs API version 23.
-- With older lua_libs, skip the file rather than fail loading it.
if require("version").api < 23 then return end

local test = require "integration_test"
local t_utils = require "integration_test.utils"
local hue_test_helpers = require "test.hue_test_helpers"
local Fields = require "fields"
local HueApi = require "hue.api"
local HueDeviceTypes = require "hue_device_types"

local BUTTON_RID = "99999999-9999-9999-9999-000000000001"
local BUTTON_DEVICE_ID = "99999999-9999-9999-9999-000000000002"
local POWER_RID = "99999999-9999-9999-9999-000000000003"
local LIGHT_RID = "99999999-9999-9999-9999-000000000011"
local MOTION_RID = "99999999-9999-9999-9999-000000000021"
local CONTACT_RID = "99999999-9999-9999-9999-000000000031"

-- The new bridge, with its records for the devices, whose state is cached.
local fixtures = hue_test_helpers.HueDeviceBuilder.new()
  :with_bridge()
  :with_button(BUTTON_RID, { battery = 85, device_id = BUTTON_DEVICE_ID, power_rid = POWER_RID })
  :with_light(LIGHT_RID, { on = { on = true } }, "white-and-color-ambiance.yml")
  :with_motion(MOTION_RID, { battery = 80 })
  :with_contact(CONTACT_RID, { battery = 75 })
  :expect_light_init_refreshes()
  :start()
local mock_bridge = fixtures.bridge
local mock_button, mock_light, mock_motion, mock_contact = table.unpack(fixtures.devices)

-- The old bridge, onboarded in an earlier run of the driver but no longer on the network, and its
-- records for the same devices.
local mock_old_bridge = test.mock_device.build_test_lan_device({
  label = "Old Hue Bridge",
  profile = t_utils.get_profile_definition("hue-bridge.yml"),
  device_network_id = "001788AABBCC",
})
local function old_record(label, profile, device_type, rid)
  return test.mock_device.build_test_lan_device({
    label = label .. " (old bridge)",
    profile = t_utils.get_profile_definition(profile),
    parent_assigned_child_key = device_type .. ":" .. rid,
    parent_device_id = mock_old_bridge.id,
  })
end
local old_records = {
  button = { mock = old_record("Hue Button", "single-button.yml", "button", BUTTON_RID), new = mock_button, rid = BUTTON_RID },
  light = { mock = old_record("Hue Light", "white-and-color-ambiance.yml", "light", LIGHT_RID), new = mock_light, rid = LIGHT_RID },
  motion = { mock = old_record("Hue Motion Sensor", "motion-sensor.yml", "motion", MOTION_RID), new = mock_motion, rid = MOTION_RID },
  contact = { mock = old_record("Hue Contact Sensor", "contact-sensor.yml", "contact", CONTACT_RID), new = mock_contact, rid = CONTACT_RID },
}

local scenario, conns = hue_test_helpers.create_hue_scenario()
hue_test_helpers.setup_button_init_expectations(conns.rest, conns.sse, fixtures.configs.button[1])
hue_test_helpers.setup_light_init_expectations(conns.rest, fixtures.configs.light[1])
hue_test_helpers.setup_motion_init_expectations(conns.rest, nil, fixtures.configs.motion[1])
hue_test_helpers.setup_contact_init_expectations(conns.rest, nil, fixtures.configs.contact[1])

hue_test_helpers.setup_scenario_test_init(function()
  -- The new records' events (from `fixtures.test_init`). An old record emitting what only an
  -- onboarded device does (supported button values, a refresh's state) would be an unexpected
  -- message.
  fixtures.test_init()
  test.mock_device.add_test_device(mock_old_bridge)
  for _, record in pairs(old_records) do
    test.mock_device.add_test_device(record.mock)
  end
  -- The fields the earlier run persisted for the old bridge (see test_hue_driver_restart.lua).
  mock_old_bridge:set_field(Fields._ADDED, true, { persist = true })
  mock_old_bridge:set_field(Fields.DEVICE_TYPE, HueDeviceTypes.BRIDGE, { persist = true })
  mock_old_bridge:set_field(Fields.BRIDGE_ID, mock_old_bridge.device_network_id, { persist = true })
  mock_old_bridge:set_field(Fields.IPV4, "192.168.1.99", { persist = true })
  mock_old_bridge:set_field(HueApi.APPLICATION_KEY_HEADER, "old-bridge-api-key", { persist = true })
  -- Unlike the other types, a light's `init` runs even when its `added` was deferred (its init
  -- copes with the missing fields), and emits levelRange whether or not the light was onboarded.
  hue_test_helpers.expect_light_init_events(old_records.light.mock, "white-and-color-ambiance.yml")
  test.socket.capability:__set_channel_ordering("relaxed")
end, scenario)

test.register_coroutine_test(
  "an old bridge's records are not set up from the new bridge's state for the same resources",
  function()
    hue_test_helpers.wait_for_init(scenario, mock_bridge)
    -- Long enough for the stray resolver's periodic retry (every 30s) to have run several times.
    test.let_time_pass(120)
    test.wait_for_events()

    local driver = fixtures.driver_device(mock_bridge).driver
    local new_by_rid = driver.hue_identifier_to_device_record_by_bridge[hue_test_helpers.BRIDGE_DNI] or {}
    for device_type, record in pairs(old_records) do
      local new = fixtures.driver_device(record.new)
      assert(new:get_field(Fields._ADDED) == true,
        string.format("expected the new bridge's %s to be onboarded", device_type))
      assert(new:get_field(Fields.HUE_DEVICE_ID) ~= nil,
        string.format("expected the new bridge's %s to have its Hue device ID", device_type))

      local old = fixtures.driver_device(record.mock)
      assert(old:get_field(Fields._ADDED) == nil,
        string.format("expected the old bridge's %s not to be added from the new bridge's state", device_type))
      assert(old:get_field(Fields.HUE_DEVICE_ID) == nil and old:get_field(Fields.DEVICE_TYPE) == nil,
        string.format("expected no Hue device fields on the old bridge's %s", device_type))
      assert(not test.mock_devices_api.__is_device_deleted(record.mock.id),
        string.format("expected the old bridge's %s not to be deleted", device_type))

      -- The resource stays registered to the new bridge's record, and isn't registered to the old one.
      assert(new_by_rid[record.rid] ~= nil and new_by_rid[record.rid].id == record.new.id,
        string.format("expected the %s's resource to stay registered to the new bridge's record", device_type))
    end
  end,
  { min_api_version = 23 }
)

test.run_registered_tests()
