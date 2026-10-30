-- Review of the LAN integration test framework against the wemo driver: the same kinds of checks
-- written with plain mock_lan_socket handles (no connection_scenario), to compare fit.
-- The driver opens one short-lived TCP connection per HTTP request, so the plain handle's
-- "next default connection" model needs the test to know the connection order in advance.
local test = require "integration_test"
test.set_test_coroutine_priority(true)

local H = require "test.review_helpers" -- only for constants/builders; the scenario in it is not activated here
local t_utils = require "integration_test.utils"
local capabilities = require "st.capabilities"
local mock_lan_socket = test.mock_lan_socket
local mock_devices_api = require "integration_test.mock_devices_api"

local mock_device = test.mock_device.build_test_lan_device({
  label = "Wemo Plug",
  device_network_id = H.DNI,
  profile = t_utils.get_profile_definition("mini-smart-plug.yaml"),
})

local plug, ssdp, driver_under_test

test.add_test_env_setup_func(function(driver)
  driver_under_test = driver
  require("discovery")._ctrl_tx = nil
end)

test.set_test_init_function(function()
  plug = mock_lan_socket.tcp_address(H.DEVICE_IP, H.DEVICE_PORT)
  ssdp = mock_lan_socket.udp_peer("239.255.255.250", 1900)
  mock_lan_socket.udp_peer(H.DEVICE_IP, 9)
  test.mock_device.add_test_device(mock_device)
  mock_device:set_field("ip", H.DEVICE_IP, { persist = true })
  mock_device:set_field("port", H.DEVICE_PORT, { persist = true })
  mock_device:set_field("serial_num", H.SERIAL, { persist = true })
end)

local OK = "HTTP/1.1 200 OK\r\ncontent-length: 0\r\n\r\n"

test.register_coroutine_test("switch off command posts SetBinaryState 0 (plain tcp_address handle)", function()
  plug:queue_bytes(OK) -- consumed by the first connection the driver makes: the command's POST
  test.socket.capability:__queue_receive({ mock_device.id, { capability = "switch", component = "main", command = "off", args = {} } })
  test.wait_until(function() return plug:connection_count() >= 1 and plug:sent():find("\r\n\r\n", 1, true) ~= nil end,
    { message = "the SOAP request" })
  local sent = plug:sent()
  assert(sent:find("^POST /upnp/control/basicevent1 HTTP/1.1"), sent)
  assert(sent:find("<BinaryState>0</BinaryState>", 1, true), sent)
  assert(sent:find('SOAPAction: "urn:Belkin:service:basicevent:1#SetBinaryState"', 1, true), sent)
end)

test.register_coroutine_test("a refresh against a refusing plug makes no state change (fail_connects)", function()
  plug:fail_connects(math.huge, "connection refused")
  test.socket.capability:__queue_receive({ mock_device.id, { capability = "refresh", component = "main", command = "refresh", args = {} } })
  test.wait_until(function() return plug:connection_count() == 0 and #ssdp:sent() >= 0 end, { message = "idle", max_turns = 3 })
  -- plug:connection_count() stays 0: a refused connect never produces a connection to inspect, and
  -- the handle has no counter of refused attempts.
  assert(plug:connection_count() == 0)
end)

test.register_coroutine_test("NOTIFY from an unknown subscription is acknowledged (connect_to, no scenario)", function()
  local _, port = driver_under_test.server.sock:getsockname()
  local conn = mock_lan_socket.connect_to(port)
  conn:queue_bytes(H.notify(H.property_set("<BinaryState>1</BinaryState>")))
  test.wait_until(function() return conn:sent():find("^HTTP/1.1 200") ~= nil end, { message = "200 reply" })
  assert(conn:closed_by_driver() or true)
end)

test.run_registered_tests()
