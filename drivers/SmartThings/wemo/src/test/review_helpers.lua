-- Shared fixture for the test_review_lan_*.lua files (review of the LAN integration test framework
-- against the wemo driver).
local test = require "integration_test"
test.set_test_coroutine_priority(true) -- required at file level for LAN tests; harmless to repeat
require "test.review_http_shim" -- socket.http is unusable under the mocks (see that file)

local t_utils = require "integration_test.utils"
local mock_lan_socket = test.mock_lan_socket
local connection_scenario = require "integration_test.connection_scenario"
local http = require "integration_test.connection_scenario_http"
local mock_devices_api = require "integration_test.mock_devices_api"

local H = {}

H.DEVICE_IP, H.DEVICE_PORT = "192.168.1.50", 49153
H.DNI = "EC1A5918ABCD" -- the MAC the device reports in setup.xml
H.SERIAL = "SER123"
H.SID = "uuid:Subscription-1"

H.setup_xml = function(over)
  over = over or {}
  return string.format([[<?xml version="1.0"?>
<root xmlns="urn:Belkin:device-1-0"><device>
<friendlyName>%s</friendlyName><modelName>%s</modelName>
<macAddress>%s</macAddress><serialNumber>%s</serialNumber>
</device></root>]], over.name or "Wemo Mini", over.model or "Socket", over.mac or H.DNI, over.serial or H.SERIAL)
end

H.ssdp_response = function(ip, port)
  return table.concat({
    "HTTP/1.1 200 OK",
    "CACHE-CONTROL: max-age=86400",
    string.format("LOCATION: http://%s:%s/setup.xml", ip or H.DEVICE_IP, port or H.DEVICE_PORT),
    "ST: urn:Belkin:device:**",
    "", "",
  }, "\r\n")
end

H.notify = function(body, sid)
  return table.concat({
    "NOTIFY / HTTP/1.1",
    "HOST: 192.168.1.2:49152",
    'CONTENT-TYPE: text/xml; charset="utf-8"',
    "NT: upnp:event",
    "NTS: upnp:propchange",
    "SID: " .. (sid or H.SID),
    "CONTENT-LENGTH: " .. #body,
    "", body,
  }, "\r\n")
end

H.property_set = function(inner)
  return '<e:propertyset xmlns:e="urn:schemas-upnp-org:event-1-0"><e:property>' .. inner ..
      "</e:property></e:propertyset>"
end

--- Build the whole fixture. `opts.known_device` (default true) makes the device already know its
--- ip/port/serial (as after a previous discovery); false leaves them unset.
function H.new(opts)
  opts = opts or {}
  local f = {}
  f.mock_device = test.mock_device.build_test_lan_device({
    label = "Wemo Plug",
    device_network_id = H.DNI,
    profile = t_utils.get_profile_definition("mini-smart-plug.yaml"),
  })

  f.scenario = connection_scenario.new({ host = H.DEVICE_IP, port = H.DEVICE_PORT })
  -- every luasocket-style request is its own TCP connection; one logical connection per endpoint
  f.setup = f.scenario:connection("setup", { matcher = http.matcher("GET", "^/setup%.xml"), ordering = "relaxed" })
  f.control = f.scenario:connection("control", { matcher = http.matcher("POST", "^/upnp/control/"), ordering = "relaxed" })
  f.events = f.scenario:connection("events",
    { matcher = http.matcher({ "SUBSCRIBE", "UNSUBSCRIBE" }, "^/upnp/event/"), ordering = "relaxed" })

  test.add_test_env_setup_func(function(driver)
    f.driver = driver
    -- `discovery` is a module-level singleton that survives from one test to the next within a file;
    -- a discovery task left over from the previous test would swallow this test's FindDevice
    -- requests (and block on a dead channel).
    require("discovery")._ctrl_tx = nil
    -- WORKAROUND for a framework gap: the mocked `devices.create_device` returns nothing, so
    -- wemo's `assert(driver:try_create_device(msg), "failed to create device record")` always fails.
    local original = driver.try_create_device
    driver.try_create_device = function(self, metadata)
      original(self, metadata)
      return true
    end
  end)

  function f.init()
    f.scenario:activate()
    -- UDP peers (like tcp_address) are forgotten when each test ends, so register them per test.
    f.ssdp = mock_lan_socket.udp_peer("239.255.255.250", 1900)
    -- protocol.subscribe finds its interface address by connecting a UDP socket to <device ip>:9
    f.discard = mock_lan_socket.udp_peer(H.DEVICE_IP, 9)
    -- The timer mock hands out queued timers in creation order (anything unqueued never fires).
    -- device_init creates: a oneshot (initial subscribe, jitter <= 2s), a 3600s interval
    -- (resubscribe) and a 60s interval (poll).
    if not opts.no_device then
      test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
      test.timer.__create_and_queue_test_time_advance_timer(3601, "interval")
      test.timer.__create_and_queue_test_time_advance_timer(61, "interval")
    end
    if opts.no_device then return end
    test.mock_device.add_test_device(f.mock_device)
    -- mock fields are consumed when the driver builds its device: set them every test.
    if opts.known_device ~= false then
      f.mock_device:set_field("ip", H.DEVICE_IP, { persist = true })
      f.mock_device:set_field("port", H.DEVICE_PORT, { persist = true })
      f.mock_device:set_field("serial_num", H.SERIAL, { persist = true })
    end
  end

  function f.is_online() return mock_devices_api.__is_device_online(f.mock_device.id) end

  --- The port the driver's subscription server listens on.
  function f.server_port()
    local _, port = f.driver.server.sock:getsockname()
    return port
  end

  --- Answer the device's own rediscovery search (device_init spawns it) and let it finish.
  function f.answer_rediscovery()
    test.wait_until(function() return #f.ssdp:sent() >= 1 end, { message = "M-SEARCH sent" })
    f.ssdp:reply(H.ssdp_response(), { from_host = H.DEVICE_IP, from_port = 1900 })
  end

  return f
end

H.http = http
return H
