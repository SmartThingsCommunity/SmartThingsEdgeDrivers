-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- Finding Sonos players by SSDP: a player the hub has no device for gets one, which is set up and
--- brought online like any other; a reply that doesn't check out is ignored; and a known player
--- that answers a later search from a new address is queried there.

-- These tests use the integration test framework's LAN support, new in lua_libs API version 23.
-- With older lua_libs, skip the file rather than fail loading it.
if require("version").api < 23 then return end

local test = require "integration_test"
local helpers = require "test.sonos_test_helpers"
local http = require "integration_test.connection_scenario_http"
local mock_devices_api = test.mock_devices_api

local NEW_IP = "192.168.1.60"

local fixture = helpers.new_fixture()
-- The player's address after it moves, for the rediscovery test.
local moved_scenario, moved_rest, moved_ws = helpers.create_scenario(NEW_IP)
helpers.register_player_expectations(moved_rest, moved_ws, { ip = NEW_IP })

-- A hub that has no Sonos device yet.
local function init_without_device()
  fixture.test_init({ no_device = true })
end

local function wait_for_search()
  test.wait_until(function() return #fixture.ssdp:sent() > 0 end, { within = 10, message = "the driver's M-SEARCH" })
end

test.register_coroutine_test(
  "a player found by SSDP gets a device, which is set up and goes online",
  function()
    local created = mock_devices_api.__expect_create_device({
      type = "LAN",
      deviceNetworkId = helpers.MAC,
      label = "Kitchen",
      profileReference = "sonos-player",
      manufacturer = "Sonos",
      model = "Sonos One",
      vendorProvidedLabel = "sonos-one",
    }, {
      adopt = {
        profile = helpers.profile(),
        -- The hub adds the device, and the driver then connects to the player it was created for.
        on_created = function(device)
          fixture.expect_init_events(device)
          fixture.expect_player_events(device)
        end,
      },
    })

    wait_for_search()
    local searches = #fixture.ssdp:sent()
    fixture.ssdp:reply(helpers.ssdp_reply(), { from_host = helpers.PLAYER_IP })
    test.wait_until(function() return created.device ~= nil end, { within = 30, message = "the device being created" })

    -- The new device looks for its player with a search of its own, which the player answers.
    test.wait_until(function() return #fixture.ssdp:sent() > searches end,
      { within = 30, message = "the new device's search for its player" })
    fixture.ssdp:reply(helpers.ssdp_reply(), { from_host = helpers.PLAYER_IP })
    test.wait_until(function() return fixture.is_online(created.device) end,
      { within = 30, message = "the new device online" })
    test.wait_for_events()

    assert(fixture.ws:was_opened(), "expected the new device to connect to its player's websocket")
  end,
  { min_api_version = 23, test_init = init_without_device }
)

test.register_coroutine_test(
  "an SSDP reply whose source address differs from its LOCATION is ignored",
  function()
    wait_for_search()
    -- Creating a device for it would be an unexpected create, which fails the test.
    fixture.ssdp:reply(helpers.ssdp_reply(), { from_host = "192.168.1.99" })
    test.let_time_pass(10)
    assert(fixture.rest:connection_count() == 0, "expected the driver not to query a player whose reply it can't trust")
  end,
  { min_api_version = 23, test_init = init_without_device }
)

test.register_coroutine_test(
  "a known player that answers a later search from a new address is queried there",
  function()
    fixture.bring_up()

    -- The driver searches again on an interval timer. The mock timer API fires such a timer only
    -- when the test queues one, at the time the test chose (600s, in this test's init): this
    -- test does not check the driver's own interval, only that it searches again when its timer
    -- fires, and the player now answers from its new address.
    local searches = #fixture.ssdp:sent()
    test.wait_until(function() return #fixture.ssdp:sent() > searches end,
      { within = 700, message = "the driver's periodic search" })
    fixture.ssdp:reply(helpers.ssdp_reply({ ip = NEW_IP }), { from_host = NEW_IP })

    -- The driver asks the player at its new address for its info, and then for its groups.
    local new_address = { ip = NEW_IP }
    http.await_request(moved_rest, "GET", "/api/v1/players/local/info", { within = 30 })
      :respond({ body = helpers.player_info(new_address) })
    http.await_request(moved_rest, "GET", "/api/v1/households/" .. helpers.HOUSEHOLD .. "/groups", { within = 30 })
      :respond({ body = helpers.groups_response(new_address) })
  end,
  {
    min_api_version = 23,
    test_init = function()
      fixture.test_init()
      moved_scenario:activate()
      test.timer.__create_and_queue_test_time_advance_timer(600, "interval")
    end,
  }
)

test.run_registered_tests()
