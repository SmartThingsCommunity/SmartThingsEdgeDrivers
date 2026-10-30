-- Review of the LAN integration test framework against the wemo driver.
-- Use case 2: connectivity loss and re-establishment. The driver polls every 60s
-- (protocol.poll); two failed requests mark the device offline, a successful one online.
local test = require "integration_test"
test.set_test_coroutine_priority(true)

local H = require "test.review_helpers"
local http = H.http
local capabilities = require "st.capabilities"
local mock_devices_api = require "integration_test.mock_devices_api"

local f = H.new()

http.expect_request(f.setup, "GET", "/setup.xml", { body = H.setup_xml(), reusable = true })
http.expect_request(f.events, "SUBSCRIBE", "/upnp/event/basicevent1", { headers = { SID = H.SID }, reusable = true })
http.expect_request(f.events, "UNSUBSCRIBE", "/upnp/event/basicevent1", { reusable = true })

test.set_test_init_function(f.init)

local function state_response(value)
  return [[<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>]] ..
      [[<u:GetBinaryStateResponse xmlns:u="urn:Belkin:service:basicevent:1"><BinaryState>]] .. value ..
      [[</BinaryState></u:GetBinaryStateResponse></s:Body></s:Envelope>]]
end

--- Rediscover (marks the device online), then let the subscribe settle.
local function online_device()
  f.answer_rediscovery()
  test.wait_until(f.is_online, { message = "device online after rediscovery" })
  test.mock_time.advance_time(2)
  test.wait_until(function() return f.mock_device:get_field("subscription_id") == H.SID end,
    { message = "subscription_id stored" })
end

local function poll_now()
  test.mock_time.advance_time(61) -- fires the 60s poll interval timer
end

test.register_coroutine_test("refused connections on the poll mark the device offline, then it recovers", function()
  online_device()
  assert(f.is_online())

  f.scenario:fail_connects(math.huge, "connection refused")
  poll_now()
  test.wait_until(function() return not f.is_online() end, { message = "device offline after failed polls" })
  assert(mock_devices_api.__count_device_status_calls(f.mock_device.id, false) >= 1)

  -- the device comes back: the next poll goes through, marks it online and reports its state
  f.scenario:clear_connect_failures()
  http.expect_request(f.control, "POST", "/upnp/control/basicevent1", { body = state_response(1) })
  test.socket.capability:__expect_send(f.mock_device:generate_test_message("main", capabilities.switch.switch.on()))
  poll_now()
  test.wait_for_events()
  test.wait_until(f.is_online, { message = "device online after recovery" })
end)

test.register_coroutine_test("a request dropped mid-flight is retried once, then the device goes offline", function()
  online_device()

  poll_now()
  local first = http.await_request(f.control, "POST", "/upnp/control/basicevent1")
  f.control:close_connection() -- the plug resets the connection without answering
  local retry = http.await_request(f.control, "POST", "/upnp/control/basicevent1")
  f.control:close_connection()
  test.wait_until(function() return not f.is_online() end, { message = "device offline after two dropped polls" })
end)

test.register_coroutine_test("a failed first poll followed by a good retry keeps the device online", function()
  online_device()

  poll_now()
  http.await_request(f.control, "POST", "/upnp/control/basicevent1")
  f.control:close_connection()
  local retry = http.await_request(f.control, "POST", "/upnp/control/basicevent1")
  test.socket.capability:__expect_send(f.mock_device:generate_test_message("main", capabilities.switch.switch.off()))
  retry:respond({ body = state_response(0) })
  test.wait_for_events()
  assert(f.is_online(), "device should still be online")
end)

test.register_coroutine_test("refresh while the plug is unreachable goes offline; refresh after it returns resubscribes and recovers", function()
  online_device()
  local refresh = { f.mock_device.id, { capability = "refresh", component = "main", command = "refresh", args = {} } }

  f.scenario:fail_connects(math.huge, "connection refused")
  test.socket.capability:__queue_receive(refresh)
  test.wait_until(function() return not f.is_online() end, { message = "offline after refresh" })
  local subscribes_before = http.count_requests(f.events, "SUBSCRIBE", "/upnp/event/basicevent1")

  f.scenario:clear_connect_failures()
  http.expect_request(f.control, "POST", "/upnp/control/basicevent1", { body = state_response(1) })
  test.socket.capability:__expect_send(f.mock_device:generate_test_message("main", capabilities.switch.switch.on()))
  test.socket.capability:__queue_receive(refresh)
  test.wait_for_events()
  test.wait_until(function()
    return f.is_online() and http.count_requests(f.events, "SUBSCRIBE", "/upnp/event/basicevent1") > subscribes_before
  end, { message = "online again and resubscribed" })
end)

test.run_registered_tests()
