-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
-- File-level test mode for every Wemo test file, which all require this module before the driver
-- loads: LAN driver tests run with test coroutine priority, so a test gets its turn to answer a
-- request or a search before mock time moves on to the driver's timeout.
test.set_test_coroutine_priority(true)
-- The driver polls each plug every 60s, for as long as the test runs. A test that is about
-- something else shouldn't have its end-of-test checks wait for (or trip over) a poll, so end it
-- shortly after its body, long enough for discovery's 5s search window to close.
test.set_post_body_time_budget(30)

local t_utils = require "integration_test.utils"
local mock_lan_socket = test.mock_lan_socket
local connection_scenario = require "integration_test.connection_scenario"
local http = require "integration_test.connection_scenario_http"
local mock_devices_api = test.mock_devices_api

--- Shared fixtures for the Wemo tests: one Wemo plug at a fixed address on the mock network, and
--- builders for the messages it and the hub exchange.
---
--- The driver talks to a plug in four ways, each of which the fixture answers on its own logical
--- connection of one connection scenario (the driver opens a new TCP connection for every HTTP
--- request, so the connections are told apart by what they ask for):
---   - `setup`: the plug's UPnP description (`GET /setup.xml`), fetched when discovery finds it;
---   - `control`: SOAP commands and state polls (`POST /upnp/control/basicevent1`);
---   - `events`: event subscriptions (`SUBSCRIBE` and `UNSUBSCRIBE /upnp/event/basicevent1`);
---   - an SSDP search on the multicast group (`ssdp`), which the plug answers by UDP.
--- The plug then reports state changes by sending a `NOTIFY` to the driver's own listening socket.
local wemo_test_helpers = {}

wemo_test_helpers.DEVICE_IP = "192.168.1.50"
wemo_test_helpers.DEVICE_PORT = 49153
--- The MAC the plug reports in setup.xml, which is also the device network id.
wemo_test_helpers.DNI = "EC1A5918ABCD"
wemo_test_helpers.SERIAL = "SER123"
--- The subscription id the plug hands out.
wemo_test_helpers.SID = "uuid:Subscription-1"

--- The plug's setup.xml. `over` can change its `name`, `model`, `mac` and `serial`.
function wemo_test_helpers.setup_xml(over)
  over = over or {}
  return string.format([[<?xml version="1.0"?>
<root xmlns="urn:Belkin:device-1-0"><device>
<friendlyName>%s</friendlyName><modelName>%s</modelName>
<macAddress>%s</macAddress><serialNumber>%s</serialNumber>
</device></root>]], over.name or "Wemo Mini", over.model or "Socket",
    over.mac or wemo_test_helpers.DNI, over.serial or wemo_test_helpers.SERIAL)
end

--- A plug's answer to an SSDP search, pointing at its setup.xml.
function wemo_test_helpers.ssdp_response(ip, port)
  return table.concat({
    "HTTP/1.1 200 OK",
    "CACHE-CONTROL: max-age=86400",
    string.format("LOCATION: http://%s:%s/setup.xml", ip or wemo_test_helpers.DEVICE_IP,
      port or wemo_test_helpers.DEVICE_PORT),
    "ST: urn:Belkin:device:**",
    "", "",
  }, "\r\n")
end

--- A UPnP event notification from the plug.
function wemo_test_helpers.notify(body, sid)
  return table.concat({
    "NOTIFY / HTTP/1.1",
    "HOST: 192.168.1.2:49152",
    'CONTENT-TYPE: text/xml; charset="utf-8"',
    "NT: upnp:event",
    "NTS: upnp:propchange",
    "SID: " .. (sid or wemo_test_helpers.SID),
    "CONTENT-LENGTH: " .. #body,
    "", body,
  }, "\r\n")
end

--- The body of a notification reporting `inner` (e.g. `<BinaryState>1</BinaryState>`).
function wemo_test_helpers.property_set(inner)
  return '<e:propertyset xmlns:e="urn:schemas-upnp-org:event-1-0"><e:property>' .. inner ..
      "</e:property></e:propertyset>"
end

--- The plug's answer to a `GetBinaryState` poll.
function wemo_test_helpers.state_response(value)
  return [[<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>]] ..
      [[<u:GetBinaryStateResponse xmlns:u="urn:Belkin:service:basicevent:1"><BinaryState>]] .. value ..
      [[</BinaryState></u:GetBinaryStateResponse></s:Body></s:Envelope>]]
end

--- Build the whole fixture. Call it at file level, then register the plug's expectations on
--- `fixture.setup`, `fixture.control` and `fixture.events` and make `fixture.init_with_device` (or
--- `fixture.init`) the file's test init function.
---
--- `opts.profile` (default "mini-smart-plug.yaml") is the profile of the plug's device. The device
--- is the plug as the driver knows it after an earlier discovery: it has its address and serial
--- number, and the port as a string, as the driver stores the one it discovered.
function wemo_test_helpers.new(opts)
  opts = opts or {}
  local fixture = {}
  fixture.mock_device = test.mock_device.build_test_lan_device({
    label = "Wemo Plug",
    device_network_id = wemo_test_helpers.DNI,
    profile = t_utils.get_profile_definition(opts.profile or "mini-smart-plug.yaml"),
  })

  fixture.scenario = connection_scenario.new({
    host = wemo_test_helpers.DEVICE_IP, port = wemo_test_helpers.DEVICE_PORT })
  fixture.setup = fixture.scenario:connection("setup",
    { matcher = http.matcher("GET", "^/setup%.xml"), ordering = "relaxed" })
  fixture.control = fixture.scenario:connection("control",
    { matcher = http.matcher("POST", "^/upnp/control/"), ordering = "relaxed" })
  fixture.events = fixture.scenario:connection("events",
    { matcher = http.matcher({ "SUBSCRIBE", "UNSUBSCRIBE" }, "^/upnp/event/"), ordering = "relaxed" })

  test.add_test_env_setup_func(function(driver)
    fixture.driver = driver
  end)

  --- A test init function that brings up the network: the plug's address, and the SSDP group.
  function fixture.init()
    -- discovery.lua keeps its running search task's channel in a module field, and the framework
    -- resets cosock between tests but not `package.loaded`. A test that fails while a search is
    -- running would leave the next test's driver talking to that dead task, so every test after
    -- the first failure would fail too: have each test's driver load the module afresh.
    package.loaded["discovery"] = nil
    fixture.scenario:activate()
    -- UDP peers (like TCP addresses) are forgotten when each test ends, so register them per test.
    fixture.ssdp = mock_lan_socket.udp_peer("239.255.255.250", 1900)
    -- protocol.subscribe finds its interface address by connecting a UDP socket to <device ip>:9
    mock_lan_socket.udp_peer(wemo_test_helpers.DEVICE_IP, 9)
  end

  --- A test init function that also starts the plug's device.
  function fixture.init_with_device()
    fixture.init()
    -- The driver's timers come from the mock timer API, which hands out the queued ones in
    -- creation order (anything unqueued never fires). device_init creates: a one-shot for the
    -- first subscription (a jitter of up to 2s), a 3600s interval to resubscribe and a 60s
    -- interval to poll.
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.timer.__create_and_queue_test_time_advance_timer(3601, "interval")
    test.timer.__create_and_queue_test_time_advance_timer(61, "interval")
    test.mock_device.add_test_device(fixture.mock_device)
    -- Mock fields are consumed when the driver builds its device, so set them in every test.
    fixture.mock_device:set_field("ip", wemo_test_helpers.DEVICE_IP, { persist = true })
    fixture.mock_device:set_field("port", tostring(wemo_test_helpers.DEVICE_PORT), { persist = true })
    fixture.mock_device:set_field("serial_num", wemo_test_helpers.SERIAL, { persist = true })
  end

  function fixture.is_online() return mock_devices_api.__is_device_online(fixture.mock_device.id) end

  --- The port the driver's subscription server listens on.
  function fixture.server_port()
    local _, port = fixture.driver.server.sock:getsockname()
    return port
  end

  --- Send the driver's listening socket a notification as the plug would (`body` is a
  --- `property_set`, `sid` defaults to the plug's subscription id), and wait for the driver to
  --- acknowledge it.
  function fixture.notify_driver(body, sid)
    local conn = mock_lan_socket.connect_to(fixture.server_port())
    conn:queue_bytes(wemo_test_helpers.notify(body, sid))
    test.wait_until(function() return conn:sent():find("^HTTP/1.1 200") ~= nil end,
      { within = 5, message = "the 200 reply to the notification" })
  end

  --- Answer the device's own rediscovery search (`init` starts it), which puts the device online.
  function fixture.answer_rediscovery()
    test.wait_until(function() return #fixture.ssdp:sent() >= 1 end,
      { within = 5, message = "the device's M-SEARCH" })
    fixture.ssdp:reply(wemo_test_helpers.ssdp_response(),
      { from_host = wemo_test_helpers.DEVICE_IP, from_port = 1900 })
    test.wait_until(fixture.is_online, { within = 5, message = "device online after rediscovery" })
  end

  --- Bring the device online and let its first subscription go through, so the driver holds the
  --- plug's subscription id.
  function fixture.online_and_subscribed()
    fixture.answer_rediscovery()
    test.wait_until(function()
      return fixture.mock_device:get_field("subscription_id") == wemo_test_helpers.SID
    end, { within = 5, message = "the device's first subscription" })
  end

  return fixture
end

wemo_test_helpers.http = http
return wemo_test_helpers
