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
    capabilities["samsungim.hueSyncMode"].mode("normal"),
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

http.expect_sse_handshake(sse, "/eventstream/clip/v2", true)

test.set_test_init_function(function()
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

--- Let the driver run until `predicate` holds (online/offline changes emit no capability events
--- for `wait_for_events` to wait on).
local function wait_until(predicate)
  test.wait_until(predicate, { message = "the expected online/offline state" })
end

local function is_online(mock_device)
  return mock_devices_api.__is_device_online(mock_device.id)
end

local function assert_online(mock_device, expected, what)
  assert(mock_devices_api.__is_device_online(mock_device.id) == expected,
    string.format("expected %s to be %s", what, expected and "online" or "offline"))
end

--- Answer the connectivity scan the driver runs when the event stream (re)opens with both lights
--- connected, so they are marked online again (and refreshed) after an outage.
local function report_lights_connected_on_reconnect()
  http.expect_request_for_test(rest, "GET", "/clip/v2/resource/zigbee_connectivity", {
    status = 200,
    body = {
      errors = {},
      data = {
        { type = "zigbee_connectivity", id = capture_payloads.ids.color_lamp_zigbee, status = "connected",
          owner = { rid = LAMP_DEVICE_ID, rtype = "device" } },
        { type = "zigbee_connectivity", id = OTHER_ZIGBEE_RID, status = "connected",
          owner = { rid = OTHER_DEVICE_ID, rtype = "device" } },
      },
    },
    reusable = true,
    prepend = true,
  })
end

local function expect_reconnect_refresh_events()
  expect_lamp_state_events(false)
  expect_other_state_events()
end

--- Assert how many times the bridge and each light were marked offline since the history was
--- last cleared.
local function assert_offline_calls(expected)
  for _, entry in ipairs({ { mock_bridge, "bridge" }, { mock_lamp, "lamp" }, { mock_other, "other light" } }) do
    local count = mock_devices_api.__count_device_status_calls(entry[1].id, false)
    assert(count == expected,
      string.format("expected the %s to be marked offline %d time(s), got %d", entry[2], expected, count))
  end
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
    report_lights_connected_on_reconnect()

    mock_devices_api.__clear_device_status_history()
    -- The bridge drops the event stream and is unreachable for the next two reconnect attempts,
    -- as in physical test scenarios 8 and 9 ("No route to host" every few seconds).
    scenario:fail_connects(2, "No route to host")
    scenario:get_connection("sse"):close_connection()
    wait_until(function() return is_online(mock_bridge) == false end)
    expect_reconnect_refresh_events()
    wait_until(function() return is_online(mock_bridge) == true end)
    assert_offline_calls(1)
    assert(mock_devices_api.__count_device_status_calls(mock_bridge.id, true) == 1,
      "expected the bridge to be marked online once, when the stream reconnected")
    wait_until(function() return is_online(mock_lamp) and is_online(mock_other) end)
    test.wait_for_events()

    -- Once the stream has reconnected and the lights are back, a later outage is reported again.
    scenario:get_connection("sse"):close_connection()
    wait_until(function() return is_online(mock_bridge) == false end)
    assert_offline_calls(2)
    expect_reconnect_refresh_events()
    wait_until(function() return is_online(mock_bridge) == true end)
    wait_until(function() return is_online(mock_lamp) and is_online(mock_other) end)
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "a light refreshed back online during an outage is marked offline again on the next failed reconnect",
  function()
    test.wait_for_events()
    mock_devices_api.__clear_device_status_history()

    -- The bridge drops the stream and rejects the next two reconnects, while its REST API still
    -- answers. The third reconnect is answered by the file's handshake.
    local reconnects = http.expect_request(sse, "GET", "/eventstream/clip/v2", { defer = true, times = 2 })
    scenario:get_connection("sse"):close_connection()
    reconnects:await():respond({ status = 503 })
    wait_until(function() return is_online(mock_lamp) == false end)
    assert(mock_devices_api.__count_device_status_calls(mock_lamp.id, false) == 1,
      "expected the lamp to be marked offline when the stream dropped")

    -- Between reconnects, a refresh reaches the lamp over REST and finds its Zigbee connection fine.
    test.socket.capability:__queue_receive({ mock_lamp.id, { capability = "refresh", component = "main", command = "refresh", args = {} } })
    expect_lamp_state_events(false)
    wait_until(function() return is_online(mock_lamp) == true end)

    -- The next failed reconnect reports it offline again.
    reconnects:await():respond({ status = 503 })
    wait_until(function() return is_online(mock_lamp) == false end)
    assert(mock_devices_api.__count_device_status_calls(mock_lamp.id, false) == 2,
      "expected the lamp to be marked offline again")
    assert(mock_devices_api.__count_device_status_calls(mock_bridge.id, false) == 1,
      "expected the bridge to be reported offline once for the outage")
    wait_until(function() return is_online(mock_bridge) == true end)
  end
)

test.register_coroutine_test(
  "while the bridge rejects event stream reconnects, devices are only marked offline once",
  function()
    test.wait_for_events()
    mock_devices_api.__clear_device_status_history()

    -- The bridge drops the stream and answers the next two reconnects with 503 (e.g. while it
    -- restarts).
    local reconnects = http.expect_request(sse, "GET", "/eventstream/clip/v2", { defer = true, times = 2 })
    scenario:get_connection("sse"):close_connection()
    wait_until(function() return is_online(mock_bridge) == false end)
    reconnects:await():respond({ status = 503 })
    reconnects:await():respond({ status = 503 })

    -- The third reconnect is answered by the file's handshake, and the stream is back.
    wait_until(function() return is_online(mock_bridge) == true end)
    assert_offline_calls(1)
  end
)

test.run_registered_tests()
