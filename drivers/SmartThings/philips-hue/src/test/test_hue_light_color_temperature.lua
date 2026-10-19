--- The colour temperature range of a light whose range isn't the driver's default.

local test = require "integration_test"
local capabilities = require "st.capabilities"
local hue_test_helpers = require "test.hue_test_helpers"
local http = require "integration_test.connection_scenario_http"

local LIGHT_RID = "55555555-5555-5555-5555-555555555555"
local HUE_DEVICE_ID = "55555555-5555-5555-5555-555555555556"
local ZIGBEE_RID = "55555555-5555-5555-5555-555555555557"

-- A white ambiance lamp reaching down to 454 mirek (2200K), rather than the default 500 (2000K).
local COLOR_TEMPERATURE = { mirek = 366, mirek_valid = true, mirek_schema = { mirek_minimum = 153, mirek_maximum = 454 } }

local fixtures = hue_test_helpers.HueDeviceBuilder.new()
  :with_bridge()
  :with_light(LIGHT_RID, {
    on = { on = true },
    dimming = { brightness = 100 },
    color_temperature = COLOR_TEMPERATURE,
    hue_device_id = HUE_DEVICE_ID,
  }, "white-ambiance.yml")
  :enable_sse()
  :start()

local mock_light = fixtures.devices[1]

local scenario, conns = hue_test_helpers.create_hue_scenario({ sse = true })
local rest, sse = conns.rest, conns.sse

-- The refreshes injected by the light's added and init handlers.
hue_test_helpers.expect_device_info(rest, HUE_DEVICE_ID,
  { { rtype = "zigbee_connectivity", rid = ZIGBEE_RID } }, { reusable = true })
hue_test_helpers.expect_zigbee_connectivity(rest, ZIGBEE_RID, { owner = HUE_DEVICE_ID, reusable = true })
http.expect_request(rest, "GET", "/clip/v2/resource/light/" .. LIGHT_RID, {
  body = { errors = {}, data = { {
    id = LIGHT_RID,
    type = "light",
    owner = { rid = HUE_DEVICE_ID, rtype = "device" },
    on = { on = true },
    dimming = { brightness = 100 },
    color_temperature = COLOR_TEMPERATURE,
  } } },
  times = 2,
})
http.expect_sse_handshake(sse, "/eventstream/clip/v2", true)

local function expect_refresh_events(first_refresh)
  local events = {
    capabilities.switch.switch.on(),
    capabilities.switchLevel.level(100),
    capabilities.colorTemperature.colorTemperature(2732),
  }
  if first_refresh then
    table.insert(events, 1, capabilities.colorTemperature.colorTemperatureRange({ minimum = 2200, maximum = 6500 }))
  end
  for _, event in ipairs(events) do
    test.socket.capability:__expect_send(mock_light:generate_test_message("main", event))
  end
end

test.set_test_init_function(function()
  scenario:activate()
  http.expect_request_for_test(rest, "GET", "/clip/v2/resource/zigbee_connectivity", {
    body = { errors = {}, data = { { owner = { rid = "unrelated-device-not-in-fixture" }, status = "connected" } } },
  })
  test.socket.capability:__set_channel_ordering("relaxed")
  expect_refresh_events(true)
  fixtures.test_init()
  expect_refresh_events(false)
end)

test.register_coroutine_test(
  "a colour temperature update without the light's mirek range keeps the range it has",
  function()
    test.wait_for_events()

    -- Updates over SSE carry the new mirek but not the light's `mirek_schema`. Any colour
    -- temperature range event (e.g. back to the default 2000K-6500K) would fail the test.
    http.queue_sse_event(sse, {
      hue_test_helpers.light_event(LIGHT_RID, true, nil, { color_temperature = { mirek = 250, mirek_valid = true } }),
    })
    test.socket.capability:__expect_send(
      mock_light:generate_test_message("main", capabilities.switch.switch.on()))
    test.socket.capability:__expect_send(
      mock_light:generate_test_message("main", capabilities.colorTemperature.colorTemperature(4000)))
    test.wait_for_events()
  end
)

test.run_registered_tests()
