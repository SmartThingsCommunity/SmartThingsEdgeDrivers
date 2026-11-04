-- Review of the LAN integration test framework against the wemo driver.
-- Use case 1: protocol message -> capability (UPnP NOTIFY into the subscription server, SOAP out).
local test = require "integration_test"
test.set_test_coroutine_priority(true)

local H = require "test.review_helpers"
local http = H.http
local capabilities = require "st.capabilities"
local mock_lan_socket = test.mock_lan_socket

local f = H.new()

http.expect_request(f.setup, "GET", "/setup.xml", { body = H.setup_xml(), reusable = true })
http.expect_request(f.events, "SUBSCRIBE", "/upnp/event/basicevent1", { headers = { SID = H.SID }, reusable = true })
-- the port we remember is a number, the rediscovered one a string, so the driver resubscribes
http.expect_request(f.events, "UNSUBSCRIBE", "/upnp/event/basicevent1", { reusable = true })
http.expect_request(f.control, "POST", "/upnp/control/basicevent1", { body = "", reusable = true })

test.set_test_init_function(f.init)

--- Rediscover, then let the initial subscribe timer fire, and wait until the driver holds a SID.
local function subscribed_device()
  f.answer_rediscovery()
  test.wait_until(function() return f.is_online() end, { message = "device online after rediscovery" })
  test.mock_time.advance_time(2)
  test.wait_until(function() return f.mock_device:get_field("subscription_id") == H.SID end,
    { message = "subscription_id stored" })
end

test.register_coroutine_test("a UPnP NOTIFY with BinaryState 1 emits switch on", function()
  subscribed_device()
  local conn = mock_lan_socket.connect_to(f.server_port())
  conn:queue_bytes(H.notify(H.property_set("<BinaryState>1</BinaryState>")))
  test.socket.capability:__expect_send(f.mock_device:generate_test_message("main", capabilities.switch.switch.on()))
  test.wait_for_events()
  test.wait_until(function() return conn:sent():find("^HTTP/1.1 200") ~= nil end, { message = "200 reply to NOTIFY" })
end)

test.register_coroutine_test("a NOTIFY with BinaryState 0 emits switch off", function()
  subscribed_device()
  local conn = mock_lan_socket.connect_to(f.server_port())
  conn:queue_bytes(H.notify(H.property_set("<BinaryState>0</BinaryState>")))
  test.socket.capability:__expect_send(f.mock_device:generate_test_message("main", capabilities.switch.switch.off()))
  test.wait_for_events()
end)

test.register_coroutine_test("a NOTIFY for an unknown SID emits nothing", function()
  subscribed_device()
  local conn = mock_lan_socket.connect_to(f.server_port())
  conn:queue_bytes(H.notify(H.property_set("<BinaryState>1</BinaryState>"), "uuid:someone-else"))
  test.wait_until(function() return conn:sent():find("^HTTP/1.1 200") ~= nil end, { message = "200 reply" })
  -- no capability message expected: the framework fails the test if one is sent
end)

test.register_coroutine_test("switch on command sends a SetBinaryState SOAP request", function()
  subscribed_device()
  test.socket.capability:__queue_receive({ f.mock_device.id, { capability = "switch", component = "main", command = "on", args = {} } })
  local req = http.await_request(f.control, "POST", "/upnp/control/basicevent1")
  assert(req.raw:find("SetBinaryState", 1, true) and req.body:find("<BinaryState>1</BinaryState>", 1, true), req.raw)
  assert(req.headers["soapaction"] and req.headers["soapaction"]:find("SetBinaryState"), "SOAPAction header")
  req:respond({ status = 200, body = "" })
  test.wait_for_events()
end)

test.run_registered_tests()
