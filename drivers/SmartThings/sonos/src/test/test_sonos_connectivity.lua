-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- An online player's device goes offline when its websocket goes away, and the driver
--- reconnects, resubscribes, and brings the device back online when the player returns.

-- These tests use the integration test framework's LAN support, new in lua_libs API version 23.
-- With older lua_libs, skip the file rather than fail loading it.
if require("version").api < 23 then return end

local test = require "integration_test"
local helpers = require "test.sonos_test_helpers"
local http = require "integration_test.connection_scenario_http"
local mock_devices_api = test.mock_devices_api

local fixture = helpers.new_fixture()
test.set_test_init_function(fixture.test_init)

--- Wait for the driver to open its websocket again and mark the device online.
local function wait_for_reconnect()
  test.wait_until(function() return fixture.ws:connection_count() == 2 and fixture.is_online() end,
    { within = 90, message = "a second websocket connection and the device online again" })
  test.wait_for_events()
end

--- Assert that the device went offline and then came back online.
local function assert_went_offline_and_back()
  local history = mock_devices_api.__get_device_status_history(fixture.device.id)
  assert(history[1] == false and history[#history] == true,
    "expected the device to go offline and then online again, got " .. #history .. " status calls")
end

--- Assert that the driver subscribed again on its second websocket connection.
local function assert_resubscribed()
  assert(#helpers.sent_ws_messages(fixture.ws, 2) == 7, "expected the 7 subscriptions again on the new connection")
end

-- However the player ends its websocket, the driver sees the connection closed. A Close frame
-- is first answered with a Close frame of its own (the vendored websocket client's closing
-- handshake), after which the player drops the TCP connection.
local ways_to_close = {
  { name = "drops its TCP connection", close = function() fixture.ws:close_connection() end },
  {
    name = "sends a Close frame and then drops its TCP connection",
    close = function()
      fixture.ws:queue_bytes(helpers.ws_close(1001, "going away"))
      test.wait_until(function()
        for _, frame in ipairs(helpers.sent_ws_frames(fixture.ws, 1)) do
          if frame.opcode == 0x8 then return true end
        end
      end, { within = 10, message = "the driver's Close frame" })
      fixture.ws:close_connection()
    end,
  },
  -- A player that crashed or rebooted: the driver's read fails with "connection reset by peer"
  -- and its writes with "closed", rather than a clean end of stream.
  { name = "resets its TCP connection", close = function() fixture.ws:reset_connection() end },
}

for _, way in ipairs(ways_to_close) do
  test.register_coroutine_test(
    "a player that " .. way.name .. " goes offline, then the driver reconnects and resubscribes",
    function()
      fixture.bring_up()
      mock_devices_api.__clear_device_status_history()

      way.close()
      wait_for_reconnect()

      assert_went_offline_and_back()
      assert_resubscribed()
    end,
    { min_api_version = 23 }
  )
end

test.register_coroutine_test(
  "a player that becomes unreachable stays offline, is retried with a backoff, and comes back online when it returns",
  function()
    fixture.bring_up()
    fixture.scenario:fail_connects(math.huge, "connection refused")
    fixture.ws:close_connection()
    test.wait_until(function() return fixture.is_online() == false end, { within = 10, message = "the device offline" })

    -- The driver retries with a growing backoff: it makes fewer attempts in the next minute than
    -- in the first half minute.
    test.let_time_pass(30)
    local first_window = fixture.scenario:failed_connect_count()
    test.let_time_pass(60)
    local second_window = fixture.scenario:failed_connect_count() - first_window
    assert(first_window >= 2, "expected the driver to keep trying to reach the player, but it made "
      .. first_window .. " attempt(s) in 30s")
    assert(second_window < first_window, string.format(
      "expected the driver to back off between attempts, but it made %d in the first 30s and %d in the next 60s",
      first_window, second_window))
    assert(fixture.is_online() == false, "the device should stay offline while the player is unreachable")

    fixture.scenario:clear_connect_failures()
    wait_for_reconnect()
  end,
  { min_api_version = 23 }
)

test.register_coroutine_test(
  "a player that accepts a REST request during a reconnect and never answers it is retried once the request times out",
  function()
    fixture.bring_up()
    -- The player's next groups request hangs; later ones are answered as usual.
    http.expect_request(fixture.rest, "GET", "/api/v1/households/" .. helpers.HOUSEHOLD .. "/groups",
      { respond = false })
    fixture.ws:close_connection()
    wait_for_reconnect()
    assert_resubscribed()
  end,
  { min_api_version = 23 }
)

test.run_registered_tests()
