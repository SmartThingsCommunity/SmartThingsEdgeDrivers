-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- Tests for colour state reported by the bridge, built from payloads recorded on real hardware
--- (see test/fixtures/capture_payloads.lua).

local test = require "integration_test"
local capabilities = require "st.capabilities"
local hue_test_helpers = require "test.hue_test_helpers"
local http = require "integration_test.connection_scenario_http"
local capture_payloads = require "test.fixtures.capture_payloads"

local LIGHT_RID = capture_payloads.ids.color_lamp_2_light
local ZIGBEE_RID = "zigbee-color-lamp-2"

-- Hue gamut A (e.g. LCT001/LLC010). The recorded lamp is gamut C, which is also the driver's
-- default gamut, so the recorded light resource is given gamut A here to make a fallback to the
-- default gamut observable.
local GAMUT_A = {
  red = { x = 0.704, y = 0.296 },
  green = { x = 0.2151, y = 0.7106 },
  blue = { x = 0.138, y = 0.08 },
}

local function light_resource()
  local resp = capture_payloads.get("color_lamp_2_light")
  resp.data[1].color.gamut = GAMUT_A
  resp.data[1].color.gamut_type = "A"
  return resp
end

local light_repr = light_resource().data[1]
local HUE_DEVICE_ID = light_repr.owner.rid

local fixtures = hue_test_helpers.HueDeviceBuilder.new()
  :with_bridge()
  :with_light(LIGHT_RID, {
    on = light_repr.on,
    dimming = light_repr.dimming,
    color = light_repr.color,
    color_temperature = light_repr.color_temperature,
    hue_device_id = HUE_DEVICE_ID,
    label = light_repr.metadata.name,
  }, "white-and-color-ambiance.yml")
  :enable_sse()
  :start()

local mock_light = fixtures.devices[1]

local scenario, conns = hue_test_helpers.create_hue_scenario({ sse = true })
local rest, sse = conns.rest, conns.sse

-- The events emitted for the recorded light resource on a refresh. The colour temperature range
-- is only emitted when it changes, i.e. on the first refresh.
local function expect_light_state_events(first_refresh)
  if first_refresh then
    test.socket.capability:__expect_send(mock_light:generate_test_message("main",
      capabilities.colorTemperature.colorTemperatureRange({ minimum = 2000, maximum = 6500 })))
  end
  for _, event in ipairs({
    capabilities["samsungim.hueSyncMode"].mode("normal"),
    capabilities.switch.switch.on(),
    capabilities.switchLevel.level(100),
    capabilities.colorTemperature.colorTemperature(2710),
    capabilities.colorControl.hue(11),
    capabilities.colorControl.saturation(54),
  }) do
    test.socket.capability:__expect_send(mock_light:generate_test_message("main", event))
  end
end

local function queue_light_refresh()
  hue_test_helpers.expect_device_info(rest, HUE_DEVICE_ID,
    { { rtype = "zigbee_connectivity", rid = ZIGBEE_RID } }, { reusable = false })
  hue_test_helpers.expect_zigbee_connectivity(rest, ZIGBEE_RID, { owner = HUE_DEVICE_ID, reusable = false })
  http.expect_request(rest, "GET", "/clip/v2/resource/light/" .. LIGHT_RID, {
    status = 200,
    body = light_resource(),
  })
end

queue_light_refresh() -- .added's injected refresh
queue_light_refresh() -- .init's injected refresh
http.expect_sse_handshake(sse, "/eventstream/clip/v2", true)

test.set_test_init_function(function()
  scenario:activate()
  http.expect_request(rest, "GET", "/clip/v2/resource/zigbee_connectivity", {
    status = 200,
    body = { errors = {}, data = {} },
    reusable = true,
  })

  test.socket.capability:__set_channel_ordering("relaxed")
  expect_light_state_events(true)
  fixtures.test_init()
  expect_light_state_events()
end)

test.register_coroutine_test(
  "a colour update emits hue and saturation without a colour temperature, and keeps the light's gamut",
  function()
    test.wait_for_events()

    -- Recorded after a setColor to red: the update carries only xy (no gamut), and the bridge
    -- reports `mirek: null, mirek_valid: false`. Any colour temperature event would fail the test.
    http.queue_sse_event(scenario:get_connection("sse"), capture_payloads.get("color_lamp_2_color_mode"))
    test.socket.capability:__expect_send(mock_light:generate_test_message("main", capabilities.colorControl.hue(2)))
    test.socket.capability:__expect_send(mock_light:generate_test_message("main", capabilities.colorControl.saturation(99)))
    test.wait_for_events()

    http.expect_request_for_test(rest, "PUT", "/clip/v2/resource/light/" .. LIGHT_RID, {
      status = 200,
      body = { data = { { rid = LIGHT_RID, rtype = "light" } }, errors = {} },
    })
    -- A later setColor still uses the light's own gamut. Pure green: clamped to gamut A's green corner, not the default (gamut C) corner at x = 0.17.
    test.socket.capability:__queue_receive({
      mock_light.id,
      { capability = "colorControl", component = "main", command = "setColor",
        args = { { hue = 100 / 3, saturation = 100 } } },
    })
    test.wait_for_events()
    http.assert_sent_json(rest, "PUT", "/clip/v2/resource/light/" .. LIGHT_RID,
      { color = { xy = { x = 0.2151, y = 0.7106 } } })
  end
)

test.run_registered_tests()
