local test = require "integration_test"
test.set_test_coroutine_priority(true)
test.set_capability_batch_receive(true)
require "test.review_lan_http_shim"

local connection_scenario = require "integration_test.connection_scenario"
local http = require "integration_test.connection_scenario_http"
local mock_mdns = test.mock_mdns
local mock_devices_api = test.mock_devices_api

local SERVICE_TYPE, DOMAIN = "_sue-st._tcp", "local"

local function speaker_event(ip, mac, name)
  local function bytes(s) return { s:byte(1, -1) } end
  return mock_mdns.build_event({
    name = name or "Speaker", service_type = SERVICE_TYPE, domain = DOMAIN, address = ip, port = 80,
    txt = { bytes("mac=" .. mac), bytes("mnid=0BE8"), bytes("setupid=604") },
  })
end

--- a harman speaker's HTTP API at ip; returns scenario, api connection
local function speaker_at(ip, label, opts)
  opts = opts or {}
  local scenario = connection_scenario.new({ host = ip, port = 80 })
  local api = scenario:connection("api", { matcher = http.matcher("GET", "^/api/"), ordering = "relaxed" })
  http.expect_request(api, "GET", "/api/setData", {
    query = nil, body = string.format("%q", "cred-" .. ip), reusable = true, optional = opts.optional,
  })
  http.expect_request(api, "GET", "/api/getData", {
    body = { { type = "string_", string_ = label } }, reusable = true,
  })
  scenario:activate()
  return scenario, api
end

local function expect_create(dni, label)
  mock_devices_api.__expect_create_device({
    deviceNetworkId = dni, label = label, profileReference = "maX10", manufacturer = "JBL",
    model = "MA510", vendorProvidedLabel = label, type = "LAN",
  })
end

test.register_coroutine_test("discovery of a speaker with a ready HTTP API creates the device", function()
  local _, api = speaker_at("192.168.1.50", "Kitchen")
  expect_create("aabbccddee01", "Kitchen")
  mock_mdns.__queue_response(SERVICE_TYPE, DOMAIN, { found = { speaker_event("192.168.1.50", "AA:BB:CC:DD:EE:01") } })
  test.socket.discovery:__queue_receive({ "start", {} })
  test.wait_for_events()
  test.socket.discovery:__queue_receive({ "stop" })
  test.wait_for_events()
  print("requests", http.count_requests(api, "GET", "/api/setData"), http.count_requests(api, "GET", "/api/getData"))
end)


local function start() test.socket.discovery:__queue_receive({ "start", {} }) end
local function stop() test.socket.discovery:__queue_receive({ "stop" }) end
local function scans() return #mock_mdns.__get_discover_calls() end

test.register_coroutine_test("mDNS finds nothing for the first scans, then the speaker appears", function()
  local _, api = speaker_at("192.168.1.51", "Den")
  expect_create("aabbccddee02", "Den")
  mock_mdns.__queue_response(SERVICE_TYPE, DOMAIN, { found = {} })
  mock_mdns.__queue_response(SERVICE_TYPE, DOMAIN, { found = {} })
  mock_mdns.__queue_response(SERVICE_TYPE, DOMAIN, { found = { speaker_event("192.168.1.51", "aa:bb:cc:dd:ee:02") } })
  start()
  test.wait_until(function() return scans() >= 2 end, { message = "two empty mDNS scans" })
  assert(http.count_requests(api, "GET", "/api/setData") == 0, "no HTTP before the device appears")
  test.wait_until(function() return http.count_requests(api, "GET", "/api/getData") >= 1 end,
    { message = "driver queried the speaker" })
  stop()
  test.wait_for_events()
end)

test.register_coroutine_test("mDNS returns the speaker but its HTTP API refuses connections at first", function()
  local scenario, api = speaker_at("192.168.1.52", "Patio")
  scenario:fail_connects(2, "connection refused")
  expect_create("aabbccddee03", "Patio")
  mock_mdns.__set_default_response(SERVICE_TYPE, DOMAIN, { found = { speaker_event("192.168.1.52", "aa:bb:cc:dd:ee:03") } })
  start()
  test.wait_until(function() return http.count_requests(api, "GET", "/api/getData") >= 1 end,
    { message = "HTTP API became ready and the driver queried it" })
  assert(scans() >= 3, "expected at least 3 scans (2 refused + 1 good), got " .. scans())
  stop()
  test.wait_for_events()
end)

test.register_coroutine_test("two speakers appear at different times", function()
  local _, api_a = speaker_at("192.168.1.53", "Left")
  local _, api_b = speaker_at("192.168.1.54", "Right")
  expect_create("aabbccddee04", "Left")
  expect_create("aabbccddee05", "Right")
  local a = speaker_event("192.168.1.53", "aa:bb:cc:dd:ee:04")
  local b = speaker_event("192.168.1.54", "aa:bb:cc:dd:ee:05")
  mock_mdns.__queue_response(SERVICE_TYPE, DOMAIN, { found = { a } })
  mock_mdns.__queue_response(SERVICE_TYPE, DOMAIN, { found = { a } })
  mock_mdns.__queue_response(SERVICE_TYPE, DOMAIN, { found = { a } })
  mock_mdns.__set_default_response(SERVICE_TYPE, DOMAIN, { found = { a, b } })
  start()
  test.wait_until(function() return http.count_requests(api_b, "GET", "/api/getData") >= 1 end,
    { message = "second speaker queried" })
  assert(http.count_requests(api_a, "GET", "/api/setData") == 1, "first speaker credential requested exactly once")
  stop()
  test.wait_for_events()
end)

test.register_coroutine_test("handoff: discovery's create_device does not make a device; the test adds it and sends `added`", function()
  local H = require "test.review_lan_ws_helpers"
  local IP = "192.168.1.70"
  local _, api = speaker_at(IP, "Office")
  local ws_scenario, ws = H.ws_scenario(IP)
  ws_scenario:activate()
  local upgrade = H.expect_upgrade(ws)
  -- the driver re-checks the active credential token before reconnecting (after the idle websocket times out)
  http.expect_request(api, "GET", "/api/getData", { prepend = true, reusable = true, optional = true,
    query = "path=settings%3A%2Fsmartthings%2FuserToken&roles=value",
    body = { { type = "string_", string_ = "cred-" .. IP } } })
  expect_create("aabbccddee20", "Office")
  mock_mdns.__queue_response(SERVICE_TYPE, DOMAIN, { found = { speaker_event(IP, "aa:bb:cc:dd:ee:20") } })
  start()
  test.wait_until(function() return http.count_requests(api, "GET", "/api/getData") >= 1 end, { message = "discovered" })
  stop()
  test.wait_for_events()
  -- Nothing created a device: the hub would now create it and send `added`; the test has to play the hub.
  local dev = H.new_device("aabbccddee20")
  test.mock_device.add_test_device(dev)
  test.socket.device_lifecycle:__queue_receive({ dev.id, "added" })
  H.accept_upgrade(upgrade)
  test.wait_until(function() return test.mock_devices_api.__is_device_online(dev.id) == true end,
    { message = "added -> init -> websocket -> online" })
  assert(dev:get_field("device_ipv4") == IP and dev:get_field("credential") == "cred-" .. IP,
    "added should have copied the discovery cache into the device fields")
  ws_scenario:fail_connects(math.huge, "connection refused")
end)

test.run_registered_tests()
