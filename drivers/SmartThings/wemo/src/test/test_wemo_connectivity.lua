-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- Tests for a plug coming and going on the network: the driver polls each plug every 60 seconds,
--- and a poll that gets no answer (after one retry) takes the device offline and a poll that does
--- puts it back online. A device finds its plug again when the driver starts by searching for it,
--- and a refresh asks the plug for its state and subscribes again.

-- These tests use the integration test framework's LAN support, new in lua_libs API version 23.
-- With older lua_libs, skip the file rather than fail loading it.
if require("version").api < 23 then return end

local test = require "integration_test"
local wemo_test_helpers = require "test.wemo_test_helpers"
local http = wemo_test_helpers.http
local capabilities = require "st.capabilities"
local mock_devices_api = test.mock_devices_api

local CONTROL = "/upnp/control/basicevent1"
local EVENTS = "/upnp/event/basicevent1"
local POLL_ACTION = '"urn:Belkin:service:basicevent:1#GetBinaryState"'

local fixture = wemo_test_helpers.new()

http.expect_request(fixture.setup, "GET", "/setup.xml", {
  body = wemo_test_helpers.setup_xml(), reusable = true })
http.expect_request(fixture.events, "SUBSCRIBE", EVENTS, {
  headers = { SID = wemo_test_helpers.SID }, reusable = true })
-- Whenever the driver resubscribes it cancels its subscription first.
http.expect_request(fixture.events, "UNSUBSCRIBE", EVENTS, { reusable = true })

test.set_test_init_function(fixture.init_with_device)

--- How many poll requests the driver has sent the plug (these tests send it no commands).
local function polls_sent()
  return http.count_requests(fixture.control, "POST", CONTROL)
end

test.register_coroutine_test(
  "polls the plug and puts the device offline after refused connections, then online again",
  function()
    fixture.online_and_subscribed()

    fixture.scenario:fail_connects(math.huge, "connection refused")
    test.wait_until(function() return not fixture.is_online() end,
      { within = 70, message = "the device offline after a failed poll" })
    -- A poll that is refused is tried once more before the device is given up on.
    assert(fixture.scenario:failed_connect_count() == 2,
      "expected the poll and its retry to be refused, got " .. fixture.scenario:failed_connect_count())

    -- The plug comes back: the next poll reports its state and puts the device online.
    fixture.scenario:clear_connect_failures()
    http.expect_request(fixture.control, "POST", CONTROL, {
      request_headers = { SOAPAction = POLL_ACTION },
      body = wemo_test_helpers.state_response(1),
    })
    test.socket.capability:__expect_send(
      fixture.mock_device:generate_test_message("main", capabilities.switch.switch.on()))
    test.wait_until(fixture.is_online, { within = 70, message = "the device online again" })
    test.wait_for_events()
  end,
  { min_api_version = 23 }
)

test.register_coroutine_test(
  "a poll the plug drops without answering is retried, and the retry keeps the device online",
  function()
    fixture.online_and_subscribed()

    http.await_request(fixture.control, "POST", CONTROL, { within = 65 })
    fixture.control:close_connection()
    local retry = http.await_request(fixture.control, "POST", CONTROL, { within = 5 })
    test.socket.capability:__expect_send(
      fixture.mock_device:generate_test_message("main", capabilities.switch.switch.off()))
    retry:respond({ body = wemo_test_helpers.state_response(0) })
    test.wait_for_events()

    assert(mock_devices_api.__count_device_status_calls(fixture.mock_device.id, false) == 0,
      "the device should never have gone offline")
  end,
  { min_api_version = 23 }
)

test.register_coroutine_test(
  "a plug that accepts a poll and never answers is taken offline once the requests time out",
  function()
    fixture.online_and_subscribed()

    -- The poll and its retry each wait for an answer for the HTTP client's 60 second timeout. (The
    -- next poll is due soon after that, so the expectation answers any number of them.)
    http.expect_request(fixture.control, "POST", CONTROL, {
      request_headers = { SOAPAction = POLL_ACTION }, respond = false, reusable = true })
    -- The poll goes out at 61s and gets no answer by 121s, when the retry goes out: the device is
    -- still online while the retry waits.
    test.let_time_pass(61 + 60 + 5)
    assert(polls_sent() == 2, "expected a poll and one retry, got " .. polls_sent())
    assert(fixture.is_online(), "the device should still be online while the retry waits")

    test.wait_until(function() return not fixture.is_online() end,
      { within = 60, message = "the device offline after the retry timed out" })
  end,
  { min_api_version = 23 }
)

test.register_coroutine_test(
  "a refresh while the plug is unreachable takes the device offline, and one after it returns recovers",
  function()
    fixture.online_and_subscribed()
    local refresh = { fixture.mock_device.id,
      { capability = "refresh", component = "main", command = "refresh", args = {} } }

    fixture.scenario:fail_connects(math.huge, "connection refused")
    test.socket.capability:__queue_receive(refresh)
    test.wait_until(function() return not fixture.is_online() end,
      { within = 5, message = "the device offline after a refresh" })
    assert(fixture.scenario:failed_connect_count() >= 2,
      "expected the refresh's poll and its retry to be refused, got " .. fixture.scenario:failed_connect_count())
    -- (No capability event is expected: the test fails if the driver sends one.)
    test.wait_for_events()

    -- The plug is back: a refresh reports its state, puts the device online and subscribes again.
    fixture.scenario:clear_connect_failures()
    local subscribes = http.count_requests(fixture.events, "SUBSCRIBE", EVENTS)
    http.expect_request(fixture.control, "POST", CONTROL, {
      request_headers = { SOAPAction = POLL_ACTION },
      body = wemo_test_helpers.state_response(1),
    })
    test.socket.capability:__expect_send(
      fixture.mock_device:generate_test_message("main", capabilities.switch.switch.on()))
    test.socket.capability:__queue_receive(refresh)
    test.wait_until(function()
      return fixture.is_online() and http.count_requests(fixture.events, "SUBSCRIBE", EVENTS) > subscribes
    end, { within = 5, message = "the device online and subscribed again" })
    test.wait_for_events()
  end,
  { min_api_version = 23 }
)

test.register_coroutine_test(
  "a device whose plug is off when it starts finds it by searching again",
  function()
    test.wait_until(function() return #fixture.ssdp:sent() >= 1 end,
      { within = 5, message = "the device's first M-SEARCH" })
    -- Nobody answers: the search window closes, and the device searches again after a short delay.
    test.wait_until(function() return #fixture.ssdp:sent() >= 2 end,
      { within = 30, message = "the device's second M-SEARCH" })
    assert(not fixture.is_online(), "the device shouldn't be online before its plug answers")

    fixture.ssdp:reply(wemo_test_helpers.ssdp_response(),
      { from_host = wemo_test_helpers.DEVICE_IP, from_port = 1900 })
    test.wait_until(fixture.is_online, { within = 5, message = "the device online once its plug answers" })
  end,
  { min_api_version = 23 }
)

test.register_coroutine_test(
  "rediscovering the plug at the address it already has doesn't subscribe again",
  function()
    fixture.online_and_subscribed()
    -- Give a second subscription time to happen, if the driver were going to make one.
    test.let_time_pass(10)
    assert(http.count_requests(fixture.events, "SUBSCRIBE", EVENTS) == 1,
      "expected only the first subscription, got " .. http.count_requests(fixture.events, "SUBSCRIBE", EVENTS))
  end,
  { min_api_version = 23 }
)

test.register_coroutine_test(
  "rediscovering the plug at a new address stores it and subscribes there",
  function()
    -- The device starts out with an address the plug has left: its first subscription (made
    -- when the jitter timer fires) is refused.
    test.let_time_pass(3)
    assert(fixture.mock_device:get_field("subscription_id") == nil)

    -- Rediscovery finds the plug elsewhere, and only that makes the driver subscribe again.
    fixture.answer_rediscovery()
    test.wait_until(function() return fixture.mock_device:get_field("subscription_id") == wemo_test_helpers.SID end,
      { within = 5, message = "the subscription at the new address" })
    assert(fixture.mock_device:get_field("ip") == wemo_test_helpers.DEVICE_IP)
    assert(http.count_requests(fixture.events, "SUBSCRIBE", EVENTS) == 1)
  end,
  {
    test_init = function()
      fixture.init_with_device()
      fixture.mock_device:set_field("ip", "192.168.1.40", { persist = true })
      test.mock_lan_socket.tcp_address("192.168.1.40", wemo_test_helpers.DEVICE_PORT)
        :fail_connects(math.huge, "connection refused")
    end,
    min_api_version = 23,
  }
)

test.register_coroutine_test(
  "a poll the plug answers with an error leaves the device online and emits nothing",
  function()
    fixture.online_and_subscribed()
    -- The answer's body would be a state if the driver took it for one.
    http.expect_request(fixture.control, "POST", CONTROL, {
      request_headers = { SOAPAction = POLL_ACTION },
      status = 500, body = wemo_test_helpers.state_response(1), reusable = true })
    test.let_time_pass(61 + 5)
    assert(polls_sent() == 1, "expected the poll, got " .. polls_sent())
    -- (No capability event is expected: the test fails if the driver sends one.)
    assert(fixture.is_online(), "the device should still be online")
    assert(mock_devices_api.__count_device_status_calls(fixture.mock_device.id, false) == 0,
      "the device should never have gone offline")
  end,
  { min_api_version = 23 }
)

test.register_coroutine_test(
  "the driver resubscribes every hour, and only the new subscription's notifications count",
  function()
    fixture.online_and_subscribed()
    local new_sid = "uuid:Subscription-2"
    http.expect_request(fixture.events, "SUBSCRIBE", EVENTS, {
      headers = { SID = new_sid }, prepend = true, reusable = true })
    -- The polls that fall due meanwhile find the plug unwell, and report nothing.
    http.expect_request(fixture.control, "POST", CONTROL, {
      request_headers = { SOAPAction = POLL_ACTION }, status = 500, reusable = true })

    test.let_time_pass(3606)
    test.wait_until(function() return fixture.mock_device:get_field("subscription_id") == new_sid end,
      { within = 5, message = "the hourly resubscription" })

    test.socket.capability:__expect_send(
      fixture.mock_device:generate_test_message("main", capabilities.switch.switch.on()))
    fixture.notify_driver(wemo_test_helpers.property_set("<BinaryState>1</BinaryState>"), new_sid)
    test.wait_for_events()
    -- The old subscription is gone (the test fails if the driver sends an event for it).
    fixture.notify_driver(wemo_test_helpers.property_set("<BinaryState>0</BinaryState>"))
    test.wait_for_events()
  end,
  { min_api_version = 23 }
)

test.run_registered_tests()
