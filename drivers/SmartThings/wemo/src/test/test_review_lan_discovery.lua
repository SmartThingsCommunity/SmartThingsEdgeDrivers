-- Review of the LAN integration test framework against the wemo driver.
-- Use case 3: SSDP discovery timing. The driver sends an M-SEARCH to 239.255.255.250:1900 one
-- second after a scan starts (so several requesters can coalesce), listens for 5 seconds, fetches
-- each responder's setup.xml, creates the device, and immediately rescans until told to stop.
local test = require "integration_test"
test.set_test_coroutine_priority(true)

local H = require "test.review_helpers"
local http = H.http
local mock_devices_api = require "integration_test.mock_devices_api"

local f = H.new({ no_device = true })

http.expect_request(f.setup, "GET", "/setup.xml", { body = H.setup_xml(), reusable = true })

test.set_test_init_function(f.init)

local function expect_created(over)
  over = over or {}
  mock_devices_api.__expect_create_device({
    deviceNetworkId = over.mac or H.DNI,
    label = over.name or "Wemo Mini",
    profileReference = over.profile or "wemo.mini-smart-plug.v1",
    manufacturer = "Belkin",
    model = over.model or "Socket",
    vendorProvidedLabel = over.name or "Wemo Mini",
    type = "LAN",
  })
end

local function start_scan() test.socket.discovery:__queue_receive({ "start", {} }) end
local function stop_scan() test.socket.discovery:__queue_receive({ "stop" }) end
local function searches_sent() return #f.ssdp:sent() end

local function wait_for_search(n)
  test.wait_until(function() return searches_sent() >= n end, { message = "M-SEARCH #" .. n })
end

test.register_coroutine_test("a scan multicasts an M-SEARCH, and a device's answer creates it", function()
  expect_created()
  start_scan()
  wait_for_search(1)
  local msg = f.ssdp:sent()[1]
  assert(msg:find("M-SEARCH * HTTP/1.1", 1, true) and msg:find('MAN: "ssdp:discover"', 1, true)
    and msg:find("ST: urn:Belkin:device:*", 1, true), msg)
  f.ssdp:reply(H.ssdp_response(), { from_host = H.DEVICE_IP, from_port = 1900 })
  test.wait_until(function() return http.count_requests(f.setup, "GET", "/setup.xml") >= 1 end,
    { message = "the driver fetches setup.xml" })
  test.wait_for_events()
  stop_scan()
  test.wait_for_events()
end)

test.register_coroutine_test("a reply late in the 5s window still creates the device", function()
  expect_created()
  start_scan()
  wait_for_search(1)
  test.mock_time.advance_time(4.5)
  f.ssdp:reply(H.ssdp_response(), { from_host = H.DEVICE_IP, from_port = 1900 })
  test.wait_until(function() return http.count_requests(f.setup, "GET", "/setup.xml") >= 1 end,
    { message = "the driver fetches setup.xml" })
  test.wait_for_events()
  stop_scan()
  test.wait_for_events()
end)

test.register_coroutine_test("a device answering only after a rescan began is found by the rescan", function()
  expect_created()
  start_scan()
  wait_for_search(1)
  -- let the first 5s window lapse with no answer; the handler loops and multicasts again
  wait_for_search(2)
  f.ssdp:reply(H.ssdp_response(), { from_host = H.DEVICE_IP, from_port = 1900 })
  test.wait_until(function() return http.count_requests(f.setup, "GET", "/setup.xml") >= 1 end,
    { message = "the driver fetches setup.xml after the rescan" })
  test.wait_for_events()
  stop_scan()
  test.wait_for_events()
end)

test.register_coroutine_test("an answer to a search whose window already closed is dropped, the next one counts", function()
  expect_created()
  start_scan()
  wait_for_search(1)
  wait_for_search(2) -- window 1 has closed and its socket is gone
  -- Replying through the peer targets "the socket that most recently sent": the rescan's socket.
  -- There is no way to address the stale first socket.
  f.ssdp:reply(H.ssdp_response(), { from_host = H.DEVICE_IP, from_port = 1900 })
  test.wait_until(function() return http.count_requests(f.setup, "GET", "/setup.xml") >= 1 end,
    { message = "setup.xml fetched" })
  test.wait_for_events()
  stop_scan()
  test.wait_for_events()
end)

test.register_coroutine_test("a device answering in two scans is only created once", function()
  expect_created()
  start_scan()
  wait_for_search(1)
  f.ssdp:reply(H.ssdp_response(), { from_host = H.DEVICE_IP, from_port = 1900 })
  test.wait_until(function() return http.count_requests(f.setup, "GET", "/setup.xml") >= 1 end,
    { message = "first setup.xml" })
  wait_for_search(2)
  f.ssdp:reply(H.ssdp_response(), { from_host = H.DEVICE_IP, from_port = 1900 })
  test.wait_until(function() return http.count_requests(f.setup, "GET", "/setup.xml") >= 2 end,
    { message = "second setup.xml" })
  test.wait_for_events()
  stop_scan()
  test.wait_for_events()
  -- the framework fails the test if a second create_device had been issued unexpectedly
end)

test.register_coroutine_test("a response whose LOCATION host differs from its source is ignored", function()
  start_scan()
  wait_for_search(1)
  f.ssdp:reply(H.ssdp_response("192.168.1.99"), { from_host = H.DEVICE_IP, from_port = 1900 })
  test.wait_for_events()
  stop_scan()
  test.wait_for_events()
  assert(http.count_requests(f.setup, "GET", "/setup.xml") == 0, "must not fetch a spoofed location")
end)

test.register_coroutine_test("an unknown model is not created", function()
  http.expect_request(f.setup, "GET", "/setup.xml", {
    body = H.setup_xml({ model = "Frobnicator" }), prepend = true, reusable = true })
  start_scan()
  wait_for_search(1)
  f.ssdp:reply(H.ssdp_response(), { from_host = H.DEVICE_IP, from_port = 1900 })
  test.wait_until(function() return http.count_requests(f.setup, "GET", "/setup.xml") >= 1 end,
    { message = "setup.xml fetched" })
  test.wait_for_events()
  stop_scan()
  test.wait_for_events()
end)

test.register_coroutine_test("stopping the scan before any answer creates nothing", function()
  start_scan()
  wait_for_search(1)
  stop_scan()
  test.wait_for_events()
end)

test.run_registered_tests()
