-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- Tests for what a plug and the hub tell each other once the plug is subscribed: UPnP event
--- notifications the plug sends to the driver's listening socket become capability events, and
--- switch commands become SOAP requests to the plug.

-- These tests use the integration test framework's LAN support, new in lua_libs API version 23.
-- With older lua_libs, skip the file rather than fail loading it.
if require("version").api < 23 then return end

local test = require "integration_test"
local wemo_test_helpers = require "test.wemo_test_helpers"
local http = wemo_test_helpers.http
local capabilities = require "st.capabilities"

local fixture = wemo_test_helpers.new()

http.expect_request(fixture.setup, "GET", "/setup.xml", {
  body = wemo_test_helpers.setup_xml(), reusable = true })
http.expect_request(fixture.events, "SUBSCRIBE", "/upnp/event/basicevent1", {
  headers = { SID = wemo_test_helpers.SID }, reusable = true })

test.set_test_init_function(fixture.init_with_device)

local notify_driver = fixture.notify_driver

for _, case in ipairs({
  { binary_state = 1, event = capabilities.switch.switch.on(), name = "on" },
  { binary_state = 0, event = capabilities.switch.switch.off(), name = "off" },
}) do
  test.register_coroutine_test(
    string.format("a notification with BinaryState %d emits switch %s", case.binary_state, case.name),
    function()
      fixture.online_and_subscribed()
      test.socket.capability:__expect_send(fixture.mock_device:generate_test_message("main", case.event))
      notify_driver(wemo_test_helpers.property_set("<BinaryState>" .. case.binary_state .. "</BinaryState>"))
      test.wait_for_events()
    end,
    { min_api_version = 23 }
  )
end

test.register_coroutine_test(
  "a notification from an unknown subscription is acknowledged but emits nothing",
  function()
    fixture.online_and_subscribed()
    -- The test fails if the driver sends a capability event for it.
    notify_driver(wemo_test_helpers.property_set("<BinaryState>1</BinaryState>"), "uuid:someone-else")
    test.wait_for_events()
  end,
  { min_api_version = 23 }
)

for _, case in ipairs({
  { command = "on", binary_state = 1 },
  { command = "off", binary_state = 0 },
}) do
  test.register_coroutine_test(
    string.format("the switch %s command sends the plug a SetBinaryState %d request", case.command, case.binary_state),
    function()
      fixture.online_and_subscribed()
      test.socket.capability:__queue_receive({
        fixture.mock_device.id,
        { capability = "switch", component = "main", command = case.command, args = {} },
      })
      local request = http.await_request(fixture.control, "POST", "/upnp/control/basicevent1", {
        request_headers = { SOAPAction = '"urn:Belkin:service:basicevent:1#SetBinaryState"' },
        within = 5,
      })
      assert(request.body:find("<BinaryState>" .. case.binary_state .. "</BinaryState>", 1, true), request.body)
      request:respond({ status = 200 })
      test.wait_for_events()
    end,
    { min_api_version = 23 }
  )
end

test.run_registered_tests()
