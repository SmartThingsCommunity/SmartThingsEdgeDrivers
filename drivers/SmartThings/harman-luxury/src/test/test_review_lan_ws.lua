local H = require "test.review_lan_ws_helpers"
local test = require "integration_test"
local capabilities = require "st.capabilities"
local connection_scenario = require "integration_test.connection_scenario"
local http = require "integration_test.connection_scenario_http"
local json = require "st.json"

local mock_device = H.new_device()
local scenario, ws = H.ws_scenario()

-- the device's HTTP API (the driver asks it for the active credential token before it reconnects)
local api_scenario = connection_scenario.new({ host = H.IP, port = 80 })
local api = api_scenario:connection("api", { matcher = http.matcher("GET", "^/api/") })
http.expect_request(api, "GET", "/api/getData", {
  body = { { type = "string_", string_ = H.TOKEN } }, reusable = true, optional = true,
})

local upgrade
test.set_test_init_function(function()
  test.mock_device.add_test_device(mock_device)
  H.seed(mock_device)
  scenario:activate()
  api_scenario:activate()
  upgrade = H.expect_upgrade(ws)
end)

local function online() return test.mock_devices_api.__is_device_online(mock_device.id) == true end
local function offline() return test.mock_devices_api.__is_device_online(mock_device.id) == false end

--- Park the driver: nothing is listening any more, so its reconnect loop keeps failing until the
--- scheduler gives up on the timers (otherwise the websocket keepalive runs on forever).
local function park() scenario:fail_connects(math.huge, "connection refused") end

local function connect()
  H.accept_upgrade(upgrade)
  test.wait_until(online, { message = "device online" })
end

local function sent_frames() return H.client_frames(ws:connection()) end
local function sent_json(i) return json.decode(sent_frames()[i].text) end

test.register_coroutine_test("UC1 (protocol->capability): websocket state updates become capability events", function()
  connect()
  test.socket.capability:__set_channel_ordering("relaxed") -- the handler's emit order is an implementation detail
  local function expect(event) test.socket.capability:__expect_send(mock_device:generate_test_message("main", event)) end
  expect(capabilities.switch.switch.on())
  expect(capabilities.audioVolume.volume(30))
  expect(capabilities.audioMute.mute.muted())
  expect(capabilities.mediaPlayback.playbackStatus.playing())
  ws:connection():queue_bytes(H.text_frame({ switch = "on", audioVolume = 30, audioMute = true,
    mediaPlayback = "play" }))
  test.wait_for_events()
  park()
end)

test.register_coroutine_test("UC1 (capability->protocol): switch on / setVolume are sent over the websocket", function()
  connect()
  test.socket.capability:__queue_receive({ mock_device.id,
    { capability = "switch", component = "main", command = "on", args = {} } })
  test.socket.capability:__queue_receive({ mock_device.id,
    { capability = "audioVolume", component = "main", command = "setVolume", args = { 42 } } })
  test.wait_until(function() return #sent_frames() >= 3 end, { message = "refresh + 2 commands sent" })
  local f1, f2, f3 = sent_json(1), sent_json(2), sent_json(3)
  assert(f1.message.command == "refresh", "first frame is the post-connect refresh")
  assert(f2.message.capability == "switch" and f2.message.command == "on" and f2.credential == H.TOKEN)
  assert(f3.message.capability == "audioVolume" and f3.message.command == "setVolume" and f3.message.arg.volume == 42)
  park()
end)

test.register_coroutine_test("UC2: no pong for the keepalive ping -> device offline; reconnects -> online", function()
  connect()
  local second_upgrade = http.expect_request_for_test(ws, "GET", "/", { defer = true })
  test.mock_devices_api.__clear_device_status_history()
  test.wait_until(offline, { max_turns = 500, message = "device offline after missed keepalive pong" })
  print("MOCK TIME when marked offline:", os.time())
  H.accept_upgrade(second_upgrade)
  test.wait_until(online, { max_turns = 500, message = "device back online after websocket reconnect" })
  assert(ws:connection_count() == 2, "expected 2 websocket connections, got " .. ws:connection_count())
  assert(test.mock_devices_api.__count_device_status_calls(mock_device.id, false) == 1, "offline exactly once")
  assert(test.mock_devices_api.__count_device_status_calls(mock_device.id, true) >= 1, "online again")
  park()
end)

test.register_coroutine_test("UC2: server drops the websocket -> reconnect", function()
  connect()
  local second_upgrade = http.expect_request_for_test(ws, "GET", "/", { defer = true })
  ws:connection():close_connection()
  H.accept_upgrade(second_upgrade)
  test.wait_until(function() return ws:connection_count() == 2 end, { max_turns = 500, message = "reconnected" })
  test.wait_until(online, { message = "online" })
  park()
end)

test.register_coroutine_test("UC2: reconnect attempts are refused twice (device rebooting) -> offline, then back online", function()
  connect()
  test.mock_devices_api.__clear_device_status_history()
  local second_upgrade = http.expect_request_for_test(ws, "GET", "/", { defer = true })
  scenario:fail_connects(2, "connection refused")
  ws:connection():close_connection()
  test.wait_until(offline, { max_turns = 500, message = "offline while connects are refused" })
  H.accept_upgrade(second_upgrade)
  test.wait_until(online, { max_turns = 500, message = "online once the device accepts connections" })
  park()
end)

test.register_coroutine_test("UC2: device comes back at a NEW IP found by mDNS (expected to work in a correct driver)", function()
  local NEW_IP = "192.168.1.61"
  local new_scenario, new_ws = H.ws_scenario(NEW_IP)
  new_scenario:activate()
  local new_api = connection_scenario.new({ host = NEW_IP, port = 80 })
  local napi = new_api:connection("api", { matcher = http.matcher("GET", "^/api/") })
  http.expect_request(napi, "GET", "/api/getData", { body = { { type = "string_", string_ = H.TOKEN } }, reusable = true, optional = true })
  new_api:activate()
  local new_upgrade = http.expect_request_for_test(new_ws, "GET", "/", { defer = true })
  connect()
  -- old IP: HTTP and websocket are both dead; mDNS now reports the speaker at the new address
  api_scenario:fail_connects(math.huge, "No route to host")
  scenario:fail_connects(math.huge, "No route to host")
  local bytes = function(s) return { s:byte(1, -1) } end
  test.mock_mdns.__set_default_response("_sue-st._tcp", "local", { found = { test.mock_mdns.build_event({
    name = "Kitchen", service_type = "_sue-st._tcp", domain = "local", address = NEW_IP, port = 80,
    txt = { bytes("mac=aa:bb:cc:dd:ee:10"), bytes("mnid=0BE8"), bytes("setupid=604") } }) } })
  ws:connection():close_connection()
  H.accept_upgrade(new_upgrade)
  test.wait_until(function() return new_ws:connection_count() == 1 and online() end,
    { max_turns = 500, message = "device reconnected at the new IP" })
  assert(mock_device:get_field("device_ipv4") == NEW_IP, "driver should have persisted the new IP")
  new_scenario:fail_connects(math.huge, "connection refused")
end)

test.run_registered_tests()
