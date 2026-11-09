-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- The driver caches device state per bridge. A Hue Bridge Pro keeps the resource IDs of the devices
--- migrated to it, so the new bridge's state for a device has the same resource ID as the old
--- bridge's record for it. With the new bridge's state cached (as right after discovery), the old
--- bridge's record must not be set up from it: it only sees its own bridge's state, and since that
--- bridge is gone, it is queued as a stray, while the new bridge's record is onboarded as usual.

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

-- The new bridge, with its record for the button, whose state is cached.
local fixtures = hue_test_helpers.HueDeviceBuilder.new()
  :with_bridge()
  :with_button(BUTTON_RID, { battery = 85, device_id = BUTTON_DEVICE_ID, power_rid = POWER_RID })
  :start()
local mock_bridge, mock_button = fixtures.bridge, fixtures.devices[1]

-- The old bridge, onboarded in an earlier run of the driver but no longer on the network, and its
-- record for the same button.
local mock_old_bridge = test.mock_device.build_test_lan_device({
  label = "Old Hue Bridge",
  profile = t_utils.get_profile_definition("hue-bridge.yml"),
  device_network_id = "001788AABBCC",
})
local mock_old_button = test.mock_device.build_test_lan_device({
  label = "Hue Button (old bridge)",
  profile = t_utils.get_profile_definition("single-button.yml"),
  parent_assigned_child_key = "button:" .. BUTTON_RID,
  parent_device_id = mock_old_bridge.id,
})

local scenario, conns = hue_test_helpers.create_hue_scenario()
hue_test_helpers.setup_button_init_expectations(conns.rest, conns.sse, fixtures.configs.button[1])

hue_test_helpers.setup_scenario_test_init(function()
  -- The new button's events: its supported button values and its refresh's battery level. The old
  -- record emitting its own supported button values would be an unexpected message.
  fixtures.test_init()
  test.mock_device.add_test_device(mock_old_bridge)
  test.mock_device.add_test_device(mock_old_button)
  -- The fields the earlier run persisted for the old bridge (see test_hue_driver_restart.lua).
  mock_old_bridge:set_field(Fields._ADDED, true, { persist = true })
  mock_old_bridge:set_field(Fields.DEVICE_TYPE, HueDeviceTypes.BRIDGE, { persist = true })
  mock_old_bridge:set_field(Fields.BRIDGE_ID, mock_old_bridge.device_network_id, { persist = true })
  mock_old_bridge:set_field(Fields.IPV4, "192.168.1.99", { persist = true })
  mock_old_bridge:set_field(HueApi.APPLICATION_KEY_HEADER, "old-bridge-api-key", { persist = true })
  test.socket.capability:__set_channel_ordering("relaxed")
end, scenario)

test.register_coroutine_test(
  "an old bridge's record is not set up from the new bridge's state for the same resource",
  function()
    hue_test_helpers.wait_for_init(scenario, mock_bridge)

    local new_button = fixtures.driver_device(mock_button)
    assert(new_button:get_field(Fields._ADDED) == true, "expected the new bridge's button to be onboarded")
    assert(new_button:get_field(Fields.HUE_DEVICE_ID) == BUTTON_DEVICE_ID,
      "expected the new bridge's button to have its Hue device ID")

    local old_button = fixtures.driver_device(mock_old_button)
    assert(old_button:get_field(Fields._ADDED) == nil,
      "expected the old bridge's button not to be added from the new bridge's state")
    assert(old_button:get_field(Fields.HUE_DEVICE_ID) == nil,
      "expected no Hue device fields on the old bridge's button")

    -- The resource stays registered to the new bridge's record, and isn't registered to the old one.
    local driver = new_button.driver
    local new_by_rid = driver.hue_identifier_to_device_record_by_bridge[hue_test_helpers.BRIDGE_DNI] or {}
    assert(new_by_rid[BUTTON_RID] ~= nil and new_by_rid[BUTTON_RID].id == mock_button.id,
      "expected the button's resource to stay registered to the new bridge's record")
  end,
  { min_api_version = 23 }
)

test.run_registered_tests()
