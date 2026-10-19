-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- Error handling in Hue light commands and refresh: error statuses, Hue API errors, missing
--- services, unparseable responses, and a keep-alive connection the bridge has closed.
---
--- A command that fails must not emit any capability events (the capability channel fails the
--- test on any it isn't expecting), and the driver must keep working afterwards.

local test = require "integration_test"
local hue_test_helpers = require "test.hue_test_helpers"
local http = require "integration_test.connection_scenario_http"

local LIGHT_RID = "11111111-1111-1111-1111-111111111111"
local LIGHT_DEVICE_ID = "22222222-2222-2222-2222-222222222222"
local LIGHT_PATH = "/clip/v2/resource/light/" .. LIGHT_RID
local DEVICE_PATH = "/clip/v2/resource/device/" .. LIGHT_DEVICE_ID

local fixtures = hue_test_helpers.HueDeviceBuilder.new()
  :with_bridge()
  :with_light(LIGHT_RID, {
    on = { on = true },
    dimming = { brightness = 100 },
    hue_device_id = LIGHT_DEVICE_ID,
  }, "white-and-color-ambiance.yml")
  :start()

local mock_bridge, mock_light = fixtures.bridge, fixtures.devices[1]

local scenario, conns = hue_test_helpers.create_hue_scenario()
local rest = conns.rest

hue_test_helpers.setup_scenario_test_init(fixtures.test_init, scenario)

local function send_command(capability, command, args)
  test.socket.capability:__queue_receive({
    mock_light.id,
    { capability = capability, component = "main", command = command, args = args or {} },
  })
  test.wait_for_events()
end

local function queue_command(capability, command, args)
  test.socket.capability:__queue_receive({
    mock_light.id,
    { capability = capability, component = "main", command = command, args = args or {} },
  })
end

local function hue_error(description, type)
  return { errors = { { type = type, description = description } }, data = {} }
end

--- After a failed command, the next one still reaches the bridge.
local function assert_next_command_sent()
  http.expect_request_for_test(rest, "PUT", LIGHT_PATH, {
    request_json = { on = { on = false } },
    body = { errors = {}, data = { { rid = LIGHT_RID, rtype = "light" } } },
  })
  send_command("switch", "off")
  scenario:assert_all_satisfied({ test_scoped_only = true })
end

test.register_coroutine_test(
  "a light command answered with 404 emits nothing and doesn't stop later commands",
  function()
    http.expect_request_for_test(rest, "PUT", LIGHT_PATH, {
      request_json = { on = { on = true } },
      status = 404,
      body = hue_error("Resource not found", "resource_not_found"),
    })
    send_command("switch", "on")
    assert_next_command_sent()
  end
)

test.register_coroutine_test(
  "a light command answered with 500 emits nothing and doesn't stop later commands",
  function()
    http.expect_request_for_test(rest, "PUT", LIGHT_PATH, {
      request_json = { dimming = { brightness = 50 } },
      status = 500,
      body = hue_error("Internal server error", "internal_error"),
    })
    send_command("switchLevel", "setLevel", { 50 })
    assert_next_command_sent()
  end
)

test.register_coroutine_test(
  "a light command answered with a Hue API error emits nothing and doesn't stop later commands",
  function()
    http.expect_request_for_test(rest, "PUT", LIGHT_PATH, {
      request_json = { on = { on = true } },
      body = hue_error("Light is unreachable"),
    })
    send_command("switch", "on")
    assert_next_command_sent()
  end
)

test.register_coroutine_test(
  "a refresh of a device without a zigbee_connectivity service doesn't query connectivity",
  function()
    hue_test_helpers.mark_bridge_initialized(mock_bridge)
    queue_command("refresh", "refresh")
    http.await_request(rest, "GET", DEVICE_PATH):respond({
      body = {
        errors = {},
        data = { { id = LIGHT_DEVICE_ID, services = { { rtype = "light", rid = LIGHT_RID } } } },
      },
    })
    test.wait_for_events()
    assert(http.count_requests(rest, "GET", "/clip/v2/resource/zigbee_connectivity", { prefix = true }) == 0,
      "expected no connectivity request without a zigbee_connectivity service")
  end
)

test.register_coroutine_test(
  "a refresh of a device the bridge no longer has (404) doesn't query connectivity",
  function()
    hue_test_helpers.mark_bridge_initialized(mock_bridge)
    queue_command("refresh", "refresh")
    http.await_request(rest, "GET", DEVICE_PATH):respond({
      status = 404,
      body = hue_error("Device not found", "resource_not_found"),
    })
    test.wait_for_events()
    assert(http.count_requests(rest, "GET", "/clip/v2/resource/zigbee_connectivity", { prefix = true }) == 0,
      "expected no connectivity request for a device the bridge doesn't have")
  end
)

test.register_coroutine_test(
  "a command answered with malformed JSON emits nothing and doesn't stop later commands",
  function()
    rest:expect_for_test({
      request = { pattern = "^PUT " .. hue_test_helpers.escape_uuid(LIGHT_PATH) },
      responses = {
        { data = http.format_response(200, { ["content-type"] = "application/json" }, "{ invalid json") }
      },
    })
    send_command("switch", "on")
    assert_next_command_sent()
  end
)

test.register_coroutine_test(
  "a command answered with an empty body emits nothing and doesn't stop later commands",
  function()
    rest:expect_for_test({
      request = { pattern = "^PUT " .. hue_test_helpers.escape_uuid(LIGHT_PATH) },
      responses = {
        { data = http.format_response(200, { ["content-type"] = "application/json" }, "") }
      },
    })
    send_command("switchLevel", "setLevel", { 25 })
    assert_next_command_sent()
  end
)

test.register_coroutine_test(
  "a command on a keep-alive connection the bridge has since closed is resent on a new connection",
  function()
    -- Physical test scenario 6: after ~90 idle minutes the first PUT went out on a connection the
    -- bridge had already closed; the driver reconnected and resent it, and the light turned on.
    local OK = { body = { data = { { rid = LIGHT_RID, rtype = "light" } }, errors = {} } }

    queue_command("switch", "on")
    local first = http.await_request(rest, "PUT", LIGHT_PATH)
    first:respond(OK)
    test.wait_for_events()

    -- The bridge closes the idle keep-alive connection. The next command goes out on it, then is
    -- resent on a new connection; the resend can follow before the test's next step, so expect
    -- both requests up front.
    rest:close_connection()
    local puts = http.expect_request(rest, "PUT", LIGHT_PATH, { defer = true, times = 2 })
    queue_command("switch", "on")
    local stale = puts:await()
    assert(stale.connection_index == first.connection_index,
      "expected the command to go out first on the connection the bridge had closed")
    local resent = puts:await()
    assert(resent.connection_index == first.connection_index + 1,
      "expected the command to be resent on a new connection")
    resent:respond(OK)
    test.wait_for_events()
  end
)

test.run_registered_tests()
