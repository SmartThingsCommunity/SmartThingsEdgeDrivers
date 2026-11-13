-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- Tests for finding Wemo plugs by SSDP. A scan sends an M-SEARCH to the multicast group one
--- second after it starts (so that several requesters can share a search), listens for answers for
--- five seconds, fetches the setup.xml of each plug that answers and creates its device, then
--- searches again until the hub stops the scan.

-- These tests use the integration test framework's LAN support, new in lua_libs API version 23.
-- With older lua_libs, skip the file rather than fail loading it.
if require("version").api < 23 then return end

local test = require "integration_test"
local wemo_test_helpers = require "test.wemo_test_helpers"
local http = wemo_test_helpers.http
local t_utils = require "integration_test.utils"

local fixture = wemo_test_helpers.new()

http.expect_request(fixture.setup, "GET", "/setup.xml", {
  body = wemo_test_helpers.setup_xml(), reusable = true })
-- A device that is already known (or one a test adopts) subscribes to its plug.
http.expect_request(fixture.events, "SUBSCRIBE", "/upnp/event/basicevent1", {
  headers = { SID = wemo_test_helpers.SID }, reusable = true })

test.set_test_init_function(fixture.init)

--- The plug answers a search: the latest one, or the `n`th that was sent.
local function plug_answers(n, response)
  fixture.ssdp:reply(response or wemo_test_helpers.ssdp_response(),
    { from_host = wemo_test_helpers.DEVICE_IP, from_port = 1900, to = n })
end

--- The metadata the driver creates the device of the plug described by `setup_xml` with. `over`
--- can change `name`, `model` and `profile` (the profile reference).
local function expected_metadata(over)
  over = over or {}
  return {
    deviceNetworkId = wemo_test_helpers.DNI,
    label = over.name or "Wemo Mini",
    profileReference = over.profile or "wemo.mini-smart-plug.v1",
    manufacturer = "Belkin",
    model = over.model or "Socket",
    vendorProvidedLabel = over.name or "Wemo Mini",
    type = "LAN",
  }
end

local function start_scan() test.socket.discovery:__queue_receive({ "start", {} }) end
local function stop_scan() test.socket.discovery:__queue_receive({ "stop" }) end

--- Let the scan run until it has sent its `n`th search, which takes a second after the scan's
--- start, or after the window of the one before it closes.
local function wait_for_search(n)
  test.wait_until(function() return #fixture.ssdp:sent() >= n end,
    { within = 10, message = "M-SEARCH #" .. n })
end

local function wait_for_setup_fetches(n)
  test.wait_until(function() return http.count_requests(fixture.setup, "GET", "/setup.xml") >= n end,
    { within = 5, message = n .. " fetch(es) of setup.xml" })
end

test.register_coroutine_test(
  "a scan multicasts an M-SEARCH, and a plug's answer creates its device",
  function()
    test.mock_devices_api.__expect_create_device(expected_metadata())
    start_scan()
    wait_for_search(1)
    local search = fixture.ssdp:sent()[1]
    assert(search:find("M-SEARCH * HTTP/1.1", 1, true) and search:find('MAN: "ssdp:discover"', 1, true)
      and search:find("ST: urn:Belkin:device:*", 1, true), search)

    plug_answers()
    wait_for_setup_fetches(1)
    test.wait_for_events()
    stop_scan()
    test.wait_for_events()
  end,
  { min_api_version = 23 }
)

test.register_coroutine_test(
  "an answer late in the five second window still creates the device",
  function()
    test.mock_devices_api.__expect_create_device(expected_metadata())
    start_scan()
    wait_for_search(1)
    -- The first search's window is still open at 4.5s. (Answer that search specifically: the
    -- latest one is already open once the window closes, so it would accept the answer anyway.)
    test.let_time_pass(4.5)
    plug_answers(1)
    wait_for_setup_fetches(1)
    test.wait_for_events()
    stop_scan()
    test.wait_for_events()
  end,
  { min_api_version = 23 }
)

test.register_coroutine_test(
  "a plug that answers only the next search is found by it",
  function()
    test.mock_devices_api.__expect_create_device(expected_metadata())
    start_scan()
    wait_for_search(1)
    -- Nobody answers the first search; its window closes and the scan searches again.
    wait_for_search(2)
    plug_answers(2)
    wait_for_setup_fetches(1)
    test.wait_for_events()
    stop_scan()
    test.wait_for_events()
  end,
  { min_api_version = 23 }
)

test.register_coroutine_test(
  "a plug that answers in two scans is only created once",
  function()
    test.mock_devices_api.__expect_create_device(expected_metadata())
    start_scan()
    wait_for_search(1)
    plug_answers(1)
    wait_for_setup_fetches(1)
    wait_for_search(2)
    plug_answers(2)
    wait_for_setup_fetches(2)
    test.wait_for_events()
    stop_scan()
    test.wait_for_events()
    -- (A second create would fail the test: only one is expected.)
  end,
  { min_api_version = 23 }
)

for _, case in ipairs({
  { model = "Socket", profile = "wemo.mini-smart-plug.v1" },
  { model = "Insight", profile = "wemo.mini-smart-plug.v1" },
  { model = "Dimmer", profile = "wemo.dimmer-switch.v1" },
  { model = "LightSwitch", profile = "wemo.light-switch.v1" },
  { model = "Lightswitch", profile = "wemo.light-switch.v1" },
  -- Motion sensors are recognized by their name, whatever their model says.
  { model = "Sensor", name = "Wemo Motion", profile = "wemo.motion-sensor.v1" },
}) do
  test.register_coroutine_test(
    string.format("a plug of model %s named %s is created with the %s profile", case.model,
      case.name or "Wemo Mini", case.profile),
    function()
      http.expect_request(fixture.setup, "GET", "/setup.xml", {
        body = wemo_test_helpers.setup_xml(case), prepend = true, reusable = true })
      test.mock_devices_api.__expect_create_device(expected_metadata(case))
      start_scan()
      wait_for_search(1)
      plug_answers()
      wait_for_setup_fetches(1)
      test.wait_for_events()
      stop_scan()
      test.wait_for_events()
    end,
    { min_api_version = 23 }
  )
end

test.register_coroutine_test(
  "a plug that is already a device of the driver isn't created again",
  function()
    start_scan()
    -- The scan's search is also the one the existing device makes to find its plug.
    fixture.answer_rediscovery()
    test.let_time_pass(1)
    wait_for_setup_fetches(1)
    stop_scan()
    test.wait_for_events()
    -- (A create would fail the test: none is expected.)
  end,
  {
    test_init = function()
      fixture.init_with_device()
    end,
    min_api_version = 23,
  }
)

test.register_coroutine_test(
  "an answer whose LOCATION host isn't the host that sent it is ignored",
  function()
    start_scan()
    wait_for_search(1)
    plug_answers(nil, wemo_test_helpers.ssdp_response("192.168.1.99"))
    test.let_time_pass(1)
    assert(http.count_requests(fixture.setup, "GET", "/setup.xml") == 0, "must not fetch a spoofed location")
    stop_scan()
    test.wait_for_events()
  end,
  { min_api_version = 23 }
)

test.register_coroutine_test(
  "a plug of an unknown model isn't created",
  function()
    http.expect_request(fixture.setup, "GET", "/setup.xml", {
      body = wemo_test_helpers.setup_xml({ model = "Frobnicator" }), prepend = true, reusable = true })
    start_scan()
    wait_for_search(1)
    plug_answers()
    wait_for_setup_fetches(1)
    test.wait_for_events()
    stop_scan()
    test.wait_for_events()
    -- (A create would fail the test: none is expected.)
  end,
  { min_api_version = 23 }
)

test.register_coroutine_test(
  "a plug whose setup.xml can't be fetched is created when it answers again",
  function()
    test.mock_devices_api.__expect_create_device(expected_metadata())
    start_scan()
    wait_for_search(1)

    fixture.scenario:fail_connects(1, "connection refused")
    plug_answers()
    test.wait_until(function() return fixture.scenario:failed_connect_count() == 1 end,
      { within = 5, message = "the refused fetch of setup.xml" })
    test.let_time_pass(1)
    assert(http.count_requests(fixture.setup, "GET", "/setup.xml") == 0)

    plug_answers()
    wait_for_setup_fetches(1)
    test.wait_for_events()
    stop_scan()
    test.wait_for_events()
  end,
  { min_api_version = 23 }
)

test.register_coroutine_test(
  "a setup.xml the plug ends by closing the connection, as Wemo plugs do, still creates the device",
  function()
    test.mock_devices_api.__expect_create_device(expected_metadata())
    -- A Wemo plug answers with a chunked body, but never sends the final zero-length chunk: it
    -- just closes the connection.
    local setup_request = http.expect_request(fixture.setup, "GET", "/setup.xml", {
      defer = true, prepend = true, persistent = false })
    start_scan()
    wait_for_search(1)
    plug_answers()
    local setup_xml = wemo_test_helpers.setup_xml()
    setup_request:await({ within = 5 }):respond_raw(table.concat({
      "HTTP/1.1 200 OK",
      "Content-Type: text/xml",
      "Transfer-Encoding: chunked",
      "", string.format("%x", #setup_xml), setup_xml, "",
    }, "\r\n"))
    fixture.setup:close_connection()

    test.wait_for_events()
    stop_scan()
    test.wait_for_events()
  end,
  { min_api_version = 23 }
)

test.register_coroutine_test(
  "a discovered plug is created as a device that goes online and subscribes to its plug",
  function()
    -- device_init sets up the plug's resubscription and poll timers.
    test.timer.__create_and_queue_test_time_advance_timer(3601, "interval")
    test.timer.__create_and_queue_test_time_advance_timer(61, "interval")

    local created = test.mock_devices_api.__expect_create_device(expected_metadata(), {
      adopt = { profile = t_utils.get_profile_definition("mini-smart-plug.yaml") },
    })
    start_scan()
    wait_for_search(1)
    plug_answers()
    test.wait_until(function() return created.device ~= nil end,
      { within = 5, message = "the plug's device being created" })
    stop_scan()
    local device = created.device

    -- The new device finds its plug (the scan's search already has it), goes online and subscribes.
    test.wait_until(function()
      return test.mock_devices_api.__is_device_online(device.id)
        and device:get_field("subscription_id") == wemo_test_helpers.SID
    end, { within = 5, message = "the new device online and subscribed" })
    assert(device:get_field("ip") == wemo_test_helpers.DEVICE_IP)
    assert(device:get_field("serial_num") == wemo_test_helpers.SERIAL)
  end,
  { min_api_version = 23 }
)

test.run_registered_tests()
