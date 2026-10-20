-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- Tests for bridge resource add/delete events over SSE, replaying event payloads recorded on real
--- hardware (see test/fixtures/capture_payloads.lua): a colour lamp being added to the bridge, the
--- smart plug being removed from it, and resource events the driver has no use for.

local test = require "integration_test"
local capabilities = require "st.capabilities"
local mock_devices_api = require "integration_test.mock_devices_api"
local hue_test_helpers = require "test.hue_test_helpers"
local http = require "integration_test.connection_scenario_http"
local capture_payloads = require "test.fixtures.capture_payloads"

local ids = capture_payloads.ids

local function plug_light_resource()
  local resp = capture_payloads.get("plug_light")
  return resp
end

local fixtures = hue_test_helpers.HueDeviceBuilder.new()
  :with_bridge()
  :with_light(ids.plug_light, { on = { on = true }, hue_device_id = ids.plug_device, label = "Hue smart plug 1" },
    "plug.yml")
  :start()

local mock_bridge, mock_plug = fixtures.bridge, fixtures.devices[1]

local scenario, conns = hue_test_helpers.create_hue_scenario()
local rest, sse = conns.rest, conns.sse

http.expect_request(rest, "GET", "/clip/v2/resource/device/" .. ids.plug_device, {
  status = 200, body = capture_payloads.get("plug_device"), reusable = true,
})
hue_test_helpers.expect_zigbee_connectivity(rest, ids.plug_zigbee, ids.plug_device, { reusable = true })
http.expect_request(rest, "GET", "/clip/v2/resource/light/" .. ids.plug_light, {
  status = 200, body = plug_light_resource(), reusable = true,
})

local function expect_plug_refresh_events()
  test.socket.capability:__set_channel_ordering("relaxed")
  test.socket.capability:__expect_send(mock_plug:generate_test_message("main", capabilities["samsungim.hueSyncMode"].mode("normal")))
  test.socket.capability:__expect_send(mock_plug:generate_test_message("main", capabilities.switch.switch.on()))
end

-- Answered once: these tests never reconnect the event stream.
http.expect_sse_handshake(sse, "/eventstream/clip/v2", false)

test.set_test_init_function(function()
  scenario:activate()
  -- The connectivity scan after the stream connects reports only a device outside the fixture.
  http.expect_request_for_test(rest, "GET", "/clip/v2/resource/zigbee_connectivity", {
    body = { errors = {}, data = { { owner = { rid = "unrelated-device-not-in-fixture" }, status = "connected" } } },
    reusable = true,
  })

  expect_plug_refresh_events() -- .added's injected refresh
  fixtures.test_init()
  expect_plug_refresh_events() -- .init's injected refresh
end)

local function sse_conn()
  test.wait_for_events()
  return scenario:get_connection("sse")
end

test.register_coroutine_test(
  "a recorded colour lamp add creates exactly one child device",
  function()
    local conn = sse_conn()

    -- The bridge sends the device together with its zigbee_connectivity, light, entertainment,
    -- motion_area_candidate and device_software_update resources; only the device add matters.
    http.expect_request_for_test(rest, "GET", "/clip/v2/resource/light/" .. ids.color_lamp_light, {
      status = 200, body = capture_payloads.get("color_lamp_light"),
    })
    mock_devices_api.__expect_create_device({
      type = "EDGE_CHILD",
      label = "Hue color lamp 1",
      profileReference = "white-and-color-ambiance",
      parentDeviceId = mock_bridge.id,
      manufacturer = "Signify Netherlands B.V.",
      model = "LCT014",
      parentAssignedChildKey = "light:" .. ids.color_lamp_light,
    })

    http.queue_sse_event(conn, capture_payloads.get("color_lamp_added"))
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "resource events for things the driver doesn't model are ignored",
  function()
    local conn = sse_conn()

    for _, name in ipairs({
      "noise_homekit",
      "noise_discovery_geolocation",
      "noise_behavior_script",
      "noise_behavior_instance",
    }) do
      http.queue_sse_event(conn, capture_payloads.get(name))
    end
    test.wait_for_events()

    assert(mock_devices_api.__is_device_online(mock_bridge.id) == true, "expected the bridge to stay online")
    assert(mock_devices_api.__is_device_online(mock_plug.id) == true, "expected the plug to stay online")
    assert(not mock_devices_api.__is_device_deleted(mock_plug.id), "expected the plug not to be deleted")
  end
)

test.register_coroutine_test(
  "a recorded smart plug removal deletes the plug",
  function()
    local conn = sse_conn()

    -- Recorded alongside the delete: the plug's room and bridge_home dropping it as a child.
    http.queue_sse_event(conn, capture_payloads.get("plug_deleted"))
    test.wait_until(function() return mock_devices_api.__is_device_deleted(mock_plug.id) end,
      { message = "the plug being deleted after the bridge reported its light resource deleted" })
  end
)

test.run_registered_tests()
