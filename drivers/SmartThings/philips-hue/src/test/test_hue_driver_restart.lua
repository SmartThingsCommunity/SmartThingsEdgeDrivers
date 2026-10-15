--- Tests for a driver restart with already-onboarded devices (physical test scenario 2): each device
--- only receives `init`, with the fields an earlier `added` persisted, and is brought up to date by
--- the refresh that follows the event stream's connectivity check rather than by re-onboarding.

local test = require "integration_test"
local capabilities = require "st.capabilities"
local mock_devices_api = require "integration_test.mock_devices_api"
local hue_test_helpers = require "test.hue_test_helpers"
local http = require "integration_test.connection_scenario_http"
local capture_payloads = require "test.fixtures.capture_payloads"
local Fields = require "fields"
local HueDeviceTypes = require "hue_device_types"

local ids = capture_payloads.ids

local function lamp_light_resource()
  local resp = capture_payloads.get("color_lamp_light")
  return resp
end

local lamp_repr = lamp_light_resource().data[1]

local fixtures = hue_test_helpers.HueDeviceBuilder.new()
  :with_bridge()
  :with_light(ids.color_lamp_light, {
    on = lamp_repr.on,
    dimming = lamp_repr.dimming,
    color = lamp_repr.color,
    color_temperature = lamp_repr.color_temperature,
    hue_device_id = ids.color_lamp_device,
    label = lamp_repr.metadata.name,
  }, "white-and-color-ambiance.yml")
  :enable_sse()
  :start()

local mock_bridge, mock_lamp = fixtures.bridge, fixtures.devices[1]

local scenario, conns = hue_test_helpers.create_hue_scenario({ sse = true })
local rest, sse = conns.rest, conns.sse

http.expect_request(rest, "GET", "/clip/v2/resource/device/" .. ids.color_lamp_device, {
  status = 200, body = capture_payloads.get("color_lamp_device"), reusable = true,
})
http.expect_request(rest, "GET", "/clip/v2/resource/zigbee_connectivity/" .. ids.color_lamp_zigbee, {
  status = 200, body = capture_payloads.get("color_lamp_zigbee"), reusable = true,
})
http.expect_request(rest, "GET", "/clip/v2/resource/light/" .. ids.color_lamp_light, {
  status = 200, body = lamp_light_resource(), reusable = true,
})

-- The fields the earlier `added` (and first `init`) left persisted.
local function seed_persisted_fields()
  mock_bridge:set_field(Fields._ADDED, true, { persist = true })
  mock_lamp:set_field(Fields.DEVICE_TYPE, HueDeviceTypes.LIGHT, { persist = true })
  mock_lamp:set_field(Fields.RESOURCE_ID, ids.color_lamp_light, { persist = true })
  mock_lamp:set_field(Fields.HUE_DEVICE_ID, ids.color_lamp_device, { persist = true })
  mock_lamp:set_field(Fields.PARENT_DEVICE_ID, mock_bridge.id, { persist = true })
  mock_lamp:set_field(Fields.GAMUT, lamp_repr.color.gamut, { persist = true })
  mock_lamp:set_field(Fields.MIN_KELVIN, 2000, { persist = true })
  mock_lamp:set_field(Fields.MAX_KELVIN, 6500, { persist = true })
  mock_lamp:set_field(Fields._ADDED, true, { persist = true })
  mock_lamp:set_field(Fields._REFRESH_AFTER_INIT, false, { persist = true })
end

test.set_test_init_function(function()
  http.expect_sse_handshake(sse, "/eventstream/clip/v2", true)
  scenario:activate()
  -- The connectivity check after the event stream opens reports the lamp connected.
  http.expect_request(rest, "GET", "/clip/v2/resource/zigbee_connectivity", {
    status = 200,
    body = { errors = {}, data = { {
      id = ids.color_lamp_zigbee,
      owner = { rid = ids.color_lamp_device, rtype = "device" },
      status = "connected",
      type = "zigbee_connectivity",
    } } },
    reusable = false,
    persistent = false,
  })

  fixtures.test_init() -- adds the devices; registers the lamp's init levelRange emit
  seed_persisted_fields()

  -- The refresh injected once the connectivity check reports the lamp connected.
  test.socket.capability:__set_channel_ordering("relaxed")
  for _, event in ipairs({
    capabilities.colorTemperature.colorTemperatureRange({ minimum = 2000, maximum = 6500 }),
    capabilities["samsungim.hueSyncMode"].mode("normal"),
    capabilities.switch.switch.on(),
    capabilities.switchLevel.level(100),
    capabilities.colorTemperature.colorTemperature(2732),
    capabilities.colorControl.hue(11),
    capabilities.colorControl.saturation(53),
  }) do
    test.socket.capability:__expect_send(mock_lamp:generate_test_message("main", event))
  end
end)

test.register_coroutine_test(
  "after a restart an onboarded light is initialized and refreshed once, without being re-added",
  function()
    for _ = 1, 20 do
      if mock_devices_api.__is_device_online(mock_lamp.id) then break end
      test.wait_for_events()
    end
    test.wait_for_events()

    assert(mock_devices_api.__is_device_online(mock_bridge.id) == true, "expected the bridge to be online")
    assert(mock_devices_api.__is_device_online(mock_lamp.id) == true, "expected the lamp to be online")

    -- One refresh: the device, connectivity and light GETs happen once each.
    local sent = rest:get_sent_log()
    local _, light_gets = sent:gsub("GET /clip/v2/resource/light/" .. hue_test_helpers.escape_uuid(ids.color_lamp_light), "")
    assert(light_gets == 1, string.format("expected 1 light refresh, got %d", light_gets))
  end
)

test.run_registered_tests()
