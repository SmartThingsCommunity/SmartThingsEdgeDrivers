-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- A button the hub adds before the driver knows its state (as after a bridge migration) is queued
--- as a "stray". Once its bridge initializes, the driver scans the bridge, finds the button there,
--- and adopts the stray: `added` runs with the button's resource ID, and the button then
--- initializes and refreshes like one that was onboarded through discovery.

-- These tests use the integration test framework's LAN support, new in lua_libs API version 23.
-- With older lua_libs, skip the file rather than fail loading it.
if require("version").api < 23 then return end

local test = require "integration_test"
local t_utils = require "integration_test.utils"
local capabilities = require "st.capabilities"
local hue_test_helpers = require "test.hue_test_helpers"
local http = require "integration_test.connection_scenario_http"
local Fields = require "fields"

local BUTTON_RID = "55555555-5555-5555-5555-000000000001"
local BUTTON_DEVICE_ID = "55555555-5555-5555-5555-000000000002"
local POWER_RID = "55555555-5555-5555-5555-000000000003"
local ZIGBEE_RID = "55555555-5555-5555-5555-000000000004"
local BUTTON_LABEL = "Hue Smart Button"

local fixtures = hue_test_helpers.HueDeviceBuilder.new()
  :with_bridge()
  :start()

local mock_bridge = fixtures.bridge

-- Not in the discovery cache, so its `added` sends it to the stray resolver.
local mock_button = test.mock_device.build_test_lan_device({
  label = BUTTON_LABEL,
  profile = t_utils.get_profile_definition("single-button.yml"),
  parent_assigned_child_key = "button:" .. BUTTON_RID,
  parent_device_id = mock_bridge.id,
})

local scenario, conns = hue_test_helpers.create_hue_scenario()
local rest = conns.rest
hue_test_helpers.setup_sse_expectations(conns.sse, rest)

local button_services = {
  { rtype = "button", rid = BUTTON_RID },
  { rtype = "device_power", rid = POWER_RID },
  { rtype = "zigbee_connectivity", rid = ZIGBEE_RID },
}
local button_device = {
  type = "device",
  id = BUTTON_DEVICE_ID,
  id_v1 = "/sensors/5",
  metadata = { name = BUTTON_LABEL, archetype = "unknown_archetype" },
  product_data = {
    manufacturer_name = "Signify Netherlands B.V.",
    model_id = "ROM001",
    product_name = BUTTON_LABEL,
  },
  services = button_services,
}

-- With a stray waiting, the bridge initializing has the driver scan the bridge's devices for it.
http.expect_request(rest, "GET", "/clip/v2/resource/device", {
  body = { errors = {}, data = { button_device } },
  reusable = true,
})
-- The scan reads the button's services to build its state; its refresh reads them again.
http.expect_request(rest, "GET", "/clip/v2/resource/device/" .. BUTTON_DEVICE_ID, {
  body = { errors = {}, data = { button_device } },
  reusable = true,
})
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
  power_state = { battery_level = 70, battery_state = "normal" },
}, { reusable = true })
hue_test_helpers.expect_zigbee_connectivity(rest, ZIGBEE_RID, BUTTON_DEVICE_ID, { reusable = true })

hue_test_helpers.setup_scenario_test_init(function()
  fixtures.test_init()
  test.mock_device.add_test_device(mock_button)
  -- What the adopted button emits: `added` its supported button values, and the refresh that
  -- follows `init` its battery level.
  test.socket.capability:__expect_send(mock_button:generate_test_message("main",
    capabilities.button.supportedButtonValues({ "pushed", "held" }, { visibility = { displayed = false } })))
  test.socket.capability:__expect_send(mock_button:generate_test_message("main",
    capabilities.battery.battery(70)))
end, scenario)

test.register_coroutine_test(
  "a stray button is adopted once its bridge reports it, then initialized",
  function()
    hue_test_helpers.wait_for_init(scenario, mock_bridge)
    local button = fixtures.driver_device(mock_button)
    test.wait_until(function() return button:get_field(Fields._INIT) == true end,
      { within = 60, message = "the stray button being adopted and initialized" })
    test.wait_for_events()

    assert(button:get_field(Fields._ADDED) == true, "expected the button to have been added")
    assert(button:get_field(Fields.RESOURCE_ID) == BUTTON_RID, "expected the button's resource ID")
    assert(button:get_field(Fields.HUE_DEVICE_ID) == BUTTON_DEVICE_ID, "expected the button's Hue device ID")
    assert(button:get_field(Fields.DEVICE_TYPE) == "button", "expected the button's device type")
    local idx_map = button:get_field(Fields.BUTTON_INDEX_MAP) or {}
    assert(idx_map[BUTTON_RID] == 1, "expected the button's resource mapped to button 1")
    assert(not test.mock_devices_api.__is_device_deleted(mock_button.id), "expected the button not to be deleted")
  end,
  { min_api_version = 23 }
)

test.run_registered_tests()
