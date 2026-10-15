--- Tests for online/offline status: per-light Zigbee connectivity reported over SSE, and losing the
--- bridge's event stream. Built from payloads recorded on real hardware (see
--- test/fixtures/capture_payloads.lua).

local test = require "integration_test"
local capabilities = require "st.capabilities"
local mock_devices_api = require "integration_test.mock_devices_api"
local hue_test_helpers = require "test.hue_test_helpers"
local http = require "integration_test.connection_scenario_http"
local capture_payloads = require "test.fixtures.capture_payloads"

local LAMP_RID = capture_payloads.ids.color_lamp_light
local LAMP_DEVICE_ID = capture_payloads.ids.color_lamp_device

local OTHER_RID = "33333333-3333-3333-3333-333333333333"
local OTHER_DEVICE_ID = "other-light-device"
local OTHER_ZIGBEE_RID = "other-light-zigbee"

local function lamp_light_resource()
  local resp = capture_payloads.get("color_lamp_light")
  -- `samsungim.hueSyncMode` (emitted for `mode`) has no definition available to the test framework.
  resp.data[1].mode = nil
  return resp
end

local lamp_repr = lamp_light_resource().data[1]

local fixtures = hue_test_helpers.HueDeviceBuilder.new()
  :with_bridge()
  :with_light(LAMP_RID, {
    on = lamp_repr.on,
    dimming = lamp_repr.dimming,
    color = lamp_repr.color,
    color_temperature = lamp_repr.color_temperature,
    hue_device_id = LAMP_DEVICE_ID,
    label = lamp_repr.metadata.name,
  }, "white-and-color-ambiance.yml")
  :with_light(OTHER_RID, { on = { on = true }, dimming = { brightness = 80 }, hue_device_id = OTHER_DEVICE_ID },
    "white.yml")
  :enable_sse()
  :start()

local mock_bridge = fixtures.bridge
local mock_lamp, mock_other = fixtures.devices[1], fixtures.devices[2]

local scenario, conns = hue_test_helpers.create_hue_scenario({ sse = true })
local rest, sse = conns.rest, conns.sse

-- The events emitted for the recorded lamp's light resource on a refresh. The colour temperature
-- range is only emitted when it changes, i.e. on the first refresh.
local function expect_lamp_state_events(first_refresh)
  if first_refresh then
    test.socket.capability:__expect_send(mock_lamp:generate_test_message("main",
      capabilities.colorTemperature.colorTemperatureRange({ minimum = 2000, maximum = 6500 })))
  end
  for _, event in ipairs({
    capabilities.switch.switch.on(),
    capabilities.switchLevel.level(100),
    capabilities.colorTemperature.colorTemperature(2732),
    capabilities.colorControl.hue(11),
    capabilities.colorControl.saturation(53),
  }) do
    test.socket.capability:__expect_send(mock_lamp:generate_test_message("main", event))
  end
end

local function expect_other_state_events()
  test.socket.capability:__expect_send(mock_other:generate_test_message("main", capabilities.switch.switch.on()))
  test.socket.capability:__expect_send(mock_other:generate_test_message("main", capabilities.switchLevel.level(80)))
end

-- Recorded REST responses for the lamp, and generic ones for the other light; reusable so they
-- serve every refresh.
http.expect_request(rest, "GET", "/clip/v2/resource/device/" .. LAMP_DEVICE_ID, {
  status = 200, body = capture_payloads.get("color_lamp_device"), reusable = true,
})
http.expect_request(rest, "GET", "/clip/v2/resource/zigbee_connectivity/" .. capture_payloads.ids.color_lamp_zigbee, {
  status = 200, body = capture_payloads.get("color_lamp_zigbee"), reusable = true,
})
http.expect_request(rest, "GET", "/clip/v2/resource/light/" .. LAMP_RID, {
  status = 200, body = lamp_light_resource(), reusable = true,
})
hue_test_helpers.expect_device_info(rest, OTHER_DEVICE_ID,
  { { rtype = "zigbee_connectivity", rid = OTHER_ZIGBEE_RID } }, { reusable = true })
hue_test_helpers.expect_zigbee_connectivity(rest, OTHER_ZIGBEE_RID, { owner = OTHER_DEVICE_ID, reusable = true })
hue_test_helpers.expect_light_resource(rest, OTHER_RID, true, 80, { reusable = true })

test.set_test_init_function(function()
  http.expect_sse_handshake(sse, "/eventstream/clip/v2", true)
  scenario:activate()
  -- Connectivity poll after the event stream opens.
  http.expect_request(rest, "GET", "/clip/v2/resource/zigbee_connectivity", {
    status = 200,
    body = { errors = {}, data = {} },
    reusable = true,
    persistent = false,
  })

  test.socket.capability:__set_channel_ordering("relaxed")
  expect_lamp_state_events(true) -- .added's injected refresh
  expect_other_state_events()
  fixtures.test_init()
  expect_lamp_state_events(false) -- .init's injected refresh
  expect_other_state_events()
end)

--- Let the driver run until `predicate` holds. Online/offline changes emit no capability events
--- for `wait_for_events` to wait on, so give the driver's threads a bounded number of turns.
local function wait_until(predicate)
  for _ = 1, 50 do
    if predicate() then return end
    test.wait_for_events()
  end
end

local function is_online(mock_device)
  return mock_devices_api.__is_device_online(mock_device.id)
end

local function assert_online(mock_device, expected, what)
  assert(mock_devices_api.__is_device_online(mock_device.id) == expected,
    string.format("expected %s to be %s", what, expected and "online" or "offline"))
end

test.register_coroutine_test(
  "a Zigbee connectivity issue for one light marks only that light offline",
  function()
    test.wait_for_events()
    assert_online(mock_lamp, true, "the lamp")

    http.queue_sse_event(scenario:get_connection("sse"), capture_payloads.get("color_lamp_connectivity_issue"))
    wait_until(function() return is_online(mock_lamp) == false end)

    assert_online(mock_lamp, false, "the lamp")
    assert_online(mock_other, true, "the other light")
    assert_online(mock_bridge, true, "the bridge")
  end
)

test.register_coroutine_test(
  "a light whose Zigbee connection comes back is marked online and refreshed",
  function()
    test.wait_for_events()
    local sse_conn = scenario:get_connection("sse")
    http.queue_sse_event(sse_conn, capture_payloads.get("color_lamp_connectivity_issue"))
    wait_until(function() return is_online(mock_lamp) == false end)
    assert_online(mock_lamp, false, "the lamp")

    http.queue_sse_event(sse_conn, capture_payloads.get("color_lamp_connected"))
    expect_lamp_state_events(false)
    test.wait_for_events()

    assert_online(mock_lamp, true, "the lamp")
  end
)

test.register_coroutine_test(
  "while the event stream keeps failing to reconnect, devices are only marked offline once",
  function()
    test.wait_for_events()
    assert_online(mock_bridge, true, "the bridge")

    local offline_calls = {}
    local device_offline = mock_devices_api.device_offline
    mock_devices_api.device_offline = function(device)
      local id = type(device) == "table" and device.id or device
      offline_calls[id] = (offline_calls[id] or 0) + 1
      return device_offline(device)
    end
    local function assert_offline_calls(expected)
      for _, entry in ipairs({ { mock_bridge, "bridge" }, { mock_lamp, "lamp" }, { mock_other, "other light" } }) do
        local count = offline_calls[entry[1].id] or 0
        assert(count == expected,
          string.format("expected the %s to be marked offline %d time(s), got %d", entry[2], expected, count))
      end
    end

    -- The bridge drops the event stream and is unreachable for the next two reconnect attempts,
    -- as in physical test scenarios 8 and 9 ("No route to host" every few seconds).
    scenario:fail_connects(2, "No route to host")
    scenario:get_connection("sse"):close_connection()
    wait_until(function() return is_online(mock_bridge) == false end)
    wait_until(function() return is_online(mock_bridge) == true end)
    assert_offline_calls(1)
    assert_online(mock_bridge, true, "the bridge")

    mock_devices_api.device_offline = device_offline
  end
)

test.run_registered_tests()
