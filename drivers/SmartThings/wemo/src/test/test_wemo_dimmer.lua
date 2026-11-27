-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- Tests for a Wemo dimmer, which also has a brightness: a switchLevel command becomes a SOAP
--- request to the plug, and the plug's brightness reports become switchLevel events.

-- These tests use the integration test framework's LAN support, new in lua_libs API version 23.
-- With older lua_libs, skip the file rather than fail loading it.
if require("version").api < 23 then return end

local test = require "integration_test"
local wemo_test_helpers = require "test.wemo_test_helpers"
local http = wemo_test_helpers.http
local capabilities = require "st.capabilities"

local fixture = wemo_test_helpers.new({ profile = "dimmer-switch.yaml" })

http.expect_request(fixture.setup, "GET", "/setup.xml", {
  body = wemo_test_helpers.setup_xml({ model = "Dimmer" }), reusable = true })
http.expect_request(fixture.events, "SUBSCRIBE", "/upnp/event/basicevent1", {
  headers = { SID = wemo_test_helpers.SID }, reusable = true })

test.set_test_init_function(fixture.init_with_device)

test.register_coroutine_test(
  "the setLevel command sends the plug a brightness",
  function()
    fixture.online_and_subscribed()
    test.socket.capability:__queue_receive({
      fixture.mock_device.id,
      { capability = "switchLevel", component = "main", command = "setLevel", args = { 40 } },
    })
    local request = http.await_request(fixture.control, "POST", "/upnp/control/basicevent1", {
      request_headers = { SOAPAction = '"urn:Belkin:service:basicevent:1#SetBinaryState"' },
      within = 5,
    })
    assert(request.body:find("<brightness>40</brightness>", 1, true), request.body)
    request:respond({ status = 200 })
    test.wait_for_events()
  end,
  { min_api_version = 23 }
)

for _, case in ipairs({
  { report = "<Brightness>75</Brightness>", event = capabilities.switchLevel.level(75), name = "a brightness of 75" },
  { report = "<Brightness>150</Brightness>", event = capabilities.switchLevel.level(100),
    name = "a brightness over 100 (as a level of 100)" },
  -- Insight-style state, where the first of several values is the power state (8 is also on).
  { report = "<BinaryState>8|1611850428|58</BinaryState>", event = capabilities.switch.switch.on(),
    name = "a multi-valued BinaryState of 8 (as switch on)" },
}) do
  test.register_coroutine_test(
    "a notification with " .. case.name .. " emits the event",
    function()
      fixture.online_and_subscribed()
      test.socket.capability:__expect_send(fixture.mock_device:generate_test_message("main", case.event))
      fixture.notify_driver(wemo_test_helpers.property_set(case.report))
      test.wait_for_events()
    end,
    { min_api_version = 23 }
  )
end

test.run_registered_tests()
