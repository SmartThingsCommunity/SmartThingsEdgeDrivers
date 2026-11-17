-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- Tests for a Wemo motion sensor, whose BinaryState reports are motion rather than a switch.

-- These tests use the integration test framework's LAN support, new in lua_libs API version 23.
-- With older lua_libs, skip the file rather than fail loading it.
if require("version").api < 23 then return end

local test = require "integration_test"
local wemo_test_helpers = require "test.wemo_test_helpers"
local http = wemo_test_helpers.http
local capabilities = require "st.capabilities"

local fixture = wemo_test_helpers.new({ profile = "motion-sensor.yaml" })

http.expect_request(fixture.setup, "GET", "/setup.xml", {
  body = wemo_test_helpers.setup_xml({ name = "Wemo Motion" }), reusable = true })
http.expect_request(fixture.events, "SUBSCRIBE", "/upnp/event/basicevent1", {
  headers = { SID = wemo_test_helpers.SID }, reusable = true })

test.set_test_init_function(fixture.init_with_device)

for _, case in ipairs({
  { binary_state = 1, event = capabilities.motionSensor.motion.active(), name = "active" },
  { binary_state = 0, event = capabilities.motionSensor.motion.inactive(), name = "inactive" },
}) do
  test.register_coroutine_test(
    string.format("a notification with BinaryState %d emits motion %s", case.binary_state, case.name),
    function()
      fixture.online_and_subscribed()
      test.socket.capability:__expect_send(fixture.mock_device:generate_test_message("main", case.event))
      fixture.notify_driver(wemo_test_helpers.property_set("<BinaryState>" .. case.binary_state .. "</BinaryState>"))
      test.wait_for_events()
    end,
    { min_api_version = 23 }
  )
end

test.run_registered_tests()
