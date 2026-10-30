-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- Discovery of Harman Luxury speakers: the driver scans for the `_sue-st._tcp` mDNS service, pairs
--- with each speaker it finds that the hub doesn't know (it asks the speaker's HTTP API for a
--- credential token and for its name) and creates the device. What happens after the device
--- exists is covered in test_harman_discovery_to_device.lua.

-- These tests use the integration test framework's LAN support, new in lua_libs API version 23.
-- With older lua_libs, skip the file rather than fail loading it.
if require("version").api < 23 then return end

local test = require "integration_test"
local H = require "test.harman_test_helpers"
local http = require "integration_test.connection_scenario_http"

local mock_mdns = test.mock_mdns

local SERVICE_TYPE, DOMAIN = "_sue-st._tcp", "local"
local ACTIVATE_TOKEN_QUERY = "path=smartthings%3AinitCredentialsToken&role=activate&value=%7B%7D"

local speaker = H.new_speaker("192.168.1.50")
local speaker_b = H.new_speaker("192.168.1.54", { label = "Right" })

test.set_test_init_function(function()
  speaker:activate()
  speaker_b:activate()
end)

local function start_discovery() test.socket.discovery:__queue_receive({ "start", {} }) end
local function stop_discovery() test.socket.discovery:__queue_receive({ "stop" }) end
local function scans() return #mock_mdns.__get_discover_calls() end
local function requests_made(api, path) return http.count_requests(api, "GET", path) end

local function announce(found)
  mock_mdns.__queue_response(SERVICE_TYPE, DOMAIN, { found = found })
end

local function expect_create(dni, label, model_info)
  test.mock_devices_api.__expect_create_device({
    type = "LAN", deviceNetworkId = dni, label = label,
    profileReference = model_info.profile or "maX10", manufacturer = model_info.manufacturer or "JBL",
    model = model_info.model or "MA510", vendorProvidedLabel = model_info.vendor_label or label,
  })
end

test.register_coroutine_test(
  "a speaker with a ready HTTP API is paired and its device created",
  function()
    -- The driver activates a new credential token and reads the speaker's name.
    http.expect_request(speaker.api, "GET", "/api/setData", { query = ACTIVATE_TOKEN_QUERY, body = H.json_string("tok-new") })
    expect_create(H.DNI, "Kitchen", {})
    announce({ H.mdns_event(speaker.ip, H.MAC) })

    start_discovery()
    test.wait_until(function() return requests_made(speaker.api, "/api/getData") >= 1 end, { within = 5 })
    stop_discovery()
    test.wait_for_events()
  end,
  { min_api_version = 23 }
)

-- The driver knows the JBL models its mDNS record names by manufacturer id (`mnid`, always 0BE8 for
-- them) and `setupid`. For one it knows it creates the device with that model's profile; for any
-- other it creates a device with the generic profile and what the speaker reports about itself.
local known_models = {
  { setup_id = "602", profile = "l42ms", model = "L75ms" },
  { setup_id = "603", profile = "l42ms", model = "L42ms" },
  { setup_id = "604", profile = "maX10", model = "MA510" },
  { setup_id = "605", profile = "maX10", model = "MA710" },
  { setup_id = "606", profile = "maX10", model = "MA7100HP" },
  { setup_id = "607", profile = "maX10", model = "MA9100HP" },
}
for _, known in ipairs(known_models) do
  test.register_coroutine_test(
    "a speaker of model " .. known.model .. " is created with its model's profile",
    function()
      expect_create(H.DNI, "Kitchen", { profile = known.profile, model = known.model })
      announce({ H.mdns_event(speaker.ip, H.MAC, { setup_id = known.setup_id }) })

      start_discovery()
      test.wait_until(function() return requests_made(speaker.api, "/api/getData") >= 1 end, { within = 5 })
      stop_discovery()
      test.wait_for_events()
    end,
    { min_api_version = 23 }
  )
end

local unknown_models = {
  { name = "an unknown setup id", mdns = { mnid = "0BE8", setup_id = "999" } },
  { name = "a manufacturer id that is not JBL's", mdns = { mnid = "FFFF", setup_id = "604" } },
}
for _, case in ipairs(unknown_models) do
  test.register_coroutine_test(
    "a speaker of an unknown model (" .. case.name .. ") is created with the details it reports about itself",
    function()
      local function reports(path, value)
        http.expect_request(speaker.api, "GET", "/api/getData", {
          query = H.get_data_query(path), body = H.string_value(value),
        })
      end
      reports("settings:/system/manufacturer", "Acme Audio")
      reports("settings:/system/modelName", "X-1")
      reports("settings:/system/productName", "Acme X-1 Speaker")
      expect_create(H.DNI, "Kitchen", {
        profile = "harman-luxury", manufacturer = "Acme Audio", model = "X-1", vendor_label = "Acme X-1 Speaker",
      })
      announce({ H.mdns_event(speaker.ip, H.MAC, case.mdns) })

      start_discovery()
      test.wait_until(function() return requests_made(speaker.api, "/api/getData") >= 4 end, { within = 5 })
      stop_discovery()
      test.wait_for_events()
    end,
    { min_api_version = 23 }
  )
end

test.register_coroutine_test(
  "discovery keeps scanning until the speaker appears",
  function()
    expect_create(H.DNI, "Kitchen", {})
    announce({})
    announce({})
    announce({ H.mdns_event(speaker.ip, H.MAC) })

    start_discovery()
    test.wait_until(function() return scans() >= 2 end, { within = 5, message = "two empty scans" })
    assert(#http.sent_requests(speaker.api) == 0, "the driver made no request before a speaker appeared")
    test.wait_until(function() return requests_made(speaker.api, "/api/getData") >= 1 end, { within = 5 })
    stop_discovery()
    test.wait_for_events()
  end,
  { min_api_version = 23 }
)

test.register_coroutine_test(
  "a speaker whose HTTP API refuses connections at first is paired once it accepts them",
  function()
    speaker.api_scenario:fail_connects(2, "connection refused")
    expect_create(H.DNI, "Kitchen", {})
    mock_mdns.__set_default_response(SERVICE_TYPE, DOMAIN, { found = { H.mdns_event(speaker.ip, H.MAC) } })

    start_discovery()
    test.wait_until(function() return requests_made(speaker.api, "/api/getData") >= 1 end, { within = 10 })
    stop_discovery()
    test.wait_for_events()

    assert(speaker.api_scenario:failed_connect_count() == 2, "expected the driver to have been refused twice")
  end,
  { min_api_version = 23 }
)

test.register_coroutine_test(
  "a speaker whose HTTP API accepts a request but never answers is retried",
  function()
    -- The first request to activate a token is accepted and never answered, so it times out.
    http.expect_request(speaker.api, "GET", "/api/setData", { prepend = true, times = 1, respond = false })
    expect_create(H.DNI, "Kitchen", {})
    mock_mdns.__set_default_response(SERVICE_TYPE, DOMAIN, { found = { H.mdns_event(speaker.ip, H.MAC) } })

    start_discovery()
    test.wait_until(function() return requests_made(speaker.api, "/api/getData") >= 1 end, { within = 30 })
    stop_discovery()
    test.wait_for_events()

    assert(requests_made(speaker.api, "/api/setData") == 2, "expected the driver to ask again after the timeout")
  end,
  { min_api_version = 23 }
)

test.register_coroutine_test(
  "a second speaker that appears later is paired without pairing the first one again",
  function()
    expect_create(H.DNI, "Kitchen", {})
    expect_create(H.DNI_B, "Right", {})
    local a = H.mdns_event(speaker.ip, H.MAC)
    local b = H.mdns_event(speaker_b.ip, H.MAC_B)
    announce({ a })
    announce({ a })
    mock_mdns.__set_default_response(SERVICE_TYPE, DOMAIN, { found = { a, b } })

    start_discovery()
    test.wait_until(function() return requests_made(speaker_b.api, "/api/getData") >= 1 end, { within = 10 })
    stop_discovery()
    test.wait_for_events()

    -- A new token replaces the speaker's current one, so pairing twice would lock out a paired hub.
    assert(requests_made(speaker.api, "/api/setData") == 1, "the first speaker was paired more than once")
  end,
  { min_api_version = 23 }
)

test.register_coroutine_test(
  "a speaker the hub already has is not paired again",
  function()
    local known = H.new_device(H.DNI)
    H.seed(known, speaker.ip)
    test.mock_device.add_test_device(known)
    -- the known device's own websocket attempts are not what this test is about
    speaker.ws_scenario:fail_connects(math.huge, "connection refused")
    announce({ H.mdns_event(speaker.ip, H.MAC) })

    start_discovery()
    test.wait_until(function() return scans() >= 1 end, { within = 5 })
    test.let_time_pass(2)
    stop_discovery()
    test.wait_for_events()

    assert(#http.sent_requests(speaker.api) == 0, "the driver made requests to a speaker it already has")
  end,
  { min_api_version = 23 }
)

test.run_registered_tests()
