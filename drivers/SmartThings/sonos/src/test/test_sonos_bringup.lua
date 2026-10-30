-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- Bringing a Sonos player online: the driver finds a player it already has a device for by SSDP,
--- reads its info and groups over REST, opens a websocket to it, subscribes to its namespaces,
--- and marks the device online.

-- These tests use the integration test framework's LAN support, new in lua_libs API version 23.
-- With older lua_libs, skip the file rather than fail loading it.
if require("version").api < 23 then return end

local test = require "integration_test"
local helpers = require "test.sonos_test_helpers"
local http = require "integration_test.connection_scenario_http"

local fixture = helpers.new_fixture()
test.set_test_init_function(fixture.test_init)

test.register_coroutine_test(
  "a known player is searched for, queried, connected over a websocket and subscribed to, and goes online",
  function()
    fixture.bring_up()

    local search = fixture.ssdp:sent()[1]
    assert(search:find("M-SEARCH * HTTP/1.1", 1, true) and search:find("ST: " .. helpers.SEARCH_TERM, 1, true),
      "expected an M-SEARCH for the Sonos search term, got: " .. search)

    -- The upgrade request is an authenticated websocket handshake over TLS.
    local connection = fixture.ws:connection()
    local upgrade = http.parse_request(connection:sent())
    assert(upgrade.path == "/websocket/api", "upgrade request path " .. tostring(upgrade.path))
    assert(upgrade.headers["upgrade"]:lower() == "websocket", "expected an Upgrade: websocket header")
    -- The driver tries each of its keys against a player and uses the first it accepts, in no
    -- fixed order, and the mock player accepts both.
    local api_key = upgrade.headers["x-sonos-api-key"]
    assert(api_key == "test-s1-key" or api_key == "test-oauth-key", "expected one of the driver's API keys, got " .. tostring(api_key))
    assert(connection:tls() and connection:tls().handshaken, "expected the websocket to be wrapped in TLS")

    -- It then subscribes, in masked frames, to the player's namespaces and its group's.
    local frames = helpers.sent_ws_frames(fixture.ws)
    for _, frame in ipairs(frames) do
      assert(frame.masked, "a client's websocket frames must be masked")
    end
    local subscribed = {}
    for _, message in ipairs(helpers.sent_ws_messages(fixture.ws)) do
      local header = message.header
      assert(header.command == "subscribe", "expected only subscribe commands, got " .. tostring(header.command))
      assert(header.householdId == helpers.HOUSEHOLD and header.groupId == helpers.GROUP_ID
        and header.playerId == helpers.PLAYER_ID, "unexpected subscription target for " .. header.namespace)
      subscribed[header.namespace] = true
    end
    for _, namespaces in ipairs({ helpers.PLAYER_SUBSCRIPTIONS, helpers.GROUP_SUBSCRIPTIONS }) do
      for _, namespace in ipairs(namespaces) do
        assert(subscribed[namespace], "expected a subscription to " .. namespace)
      end
    end
    assert(#frames == 7, "expected exactly 7 subscribe frames, got " .. #frames)
  end,
  { min_api_version = 23 }
)

test.run_registered_tests()
