-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local connection_scenario = require "integration_test.connection_scenario"
local http = require "integration_test.connection_scenario_http"
local mock_mdns = test.mock_mdns
local mock_devices_api = test.mock_devices_api

local Discovery = require "disco"

local BRIDGE_IP = "192.168.1.20"
local BRIDGE_MAC = "aa-bb-cc-dd-ee-ff"
local BRIDGE_DNI = "AABBCCDDEEFF" -- BRIDGE_MAC with separators stripped, uppercased
local BRIDGE_NAME = "Living Room"

test.add_test_env_setup_func(function(driver)
  -- disco is a module-level singleton that persists across tests within this file; a stale
  -- discovery_active=true (e.g. left over from an interrupted prior run) would make
  -- HueDiscovery.discover silently no-op.
  Discovery.discovery_active = false
  Discovery.api_keys = {}
  Discovery.disco_api_instances = {}
end)

local function test_init()
  -- No bridge device is pre-registered here -- discovering and creating it is exactly what
  -- these tests exercise. Discovery rescans every second until stopped, so let the test act as
  -- soon as the driver waits rather than only once mock time has run far ahead.
  test.set_test_coroutine_priority(true)
end

test.set_test_init_function(test_init)

--- Queue an mDNS response for the bridge and start discovery via the same "discovery" channel
--- message the real hub sends when a user initiates a scan (see
--- st.handlers.discovery_message_handlers), rather than invoking Discovery.discover directly:
--- that function makes real (mocked) blocking REST calls internally via cosock, which only
--- works correctly inside a real cosock-managed thread -- exactly what the framework's own
--- discovery dispatch spins up, and what the test coroutine itself is not.
local function start_discovery()
  mock_mdns.__queue_response(Discovery.ServiceType, Discovery.Domain, {
    found = {
      mock_mdns.build_event({
        name = "Hue Bridge",
        service_type = Discovery.ServiceType,
        domain = Discovery.Domain,
        address = BRIDGE_IP,
        port = 443,
      }),
    },
  })
  test.socket.discovery:__queue_receive({ "start", {} })
end

--- Discovery.discover loops "scan, sleep 1s" until told to stop; without this it would keep
--- retrying (and re-sending requests) forever.
local function stop_discovery()
  test.socket.discovery:__queue_receive({ "stop" })
end

--- A bridge at `ip` answering the config request and the API key requests discovery makes (it
--- keeps asking for a key until one is handed out or discovery stops).
--- @return table scenario, already activated
--- @return table api the connection discovery's requests are made on
local function bridge_at(ip, config, key_response)
  local scenario = connection_scenario.new({ host = ip, port = 443 })
  local api = scenario:connection("api", { matcher = http.matcher({ "GET", "POST" }, "^/api"), ordering = "relaxed" })
  http.expect_request(api, "GET", "/api/config", { body = config })
  http.expect_request(api, "POST", "/api", {
    request_json = { devicetype = "smartthings_edge_driver#" .. ip, generateclientkey = true },
    body = key_response,
    reusable = true,
  })
  return scenario:activate(), api
end

--- Assert that discovery fetched the bridge's config and asked it for an API key.
local function assert_bridge_queried(bridge, api)
  bridge:assert_all_satisfied()
  assert(http.count_requests(api, "POST", "/api") >= 1, "expected discovery to request an API key")
end

test.register_coroutine_test(
  "mDNS discovery finds a bridge and requests an API key, but does not create a device if the Link Button hasn't been pressed",
  function()
    local bridge, api = bridge_at(BRIDGE_IP, {
      mac = BRIDGE_MAC,
      swversion = "1968054000",
      modelid = "BSB002",
      name = BRIDGE_NAME,
    }, {
      { error = { type = 101, address = "/", description = "link button not pressed" } },
    })

    start_discovery()
    test.wait_for_events()
    stop_discovery()
    test.wait_for_events()

    assert_bridge_queried(bridge, api)
  end
)

test.register_coroutine_test(
  "mDNS discovery creates a bridge device once an API key is obtained",
  function()
    local bridge, api = bridge_at(BRIDGE_IP, {
      mac = BRIDGE_MAC,
      swversion = "1968054000",
      modelid = "BSB002",
      name = BRIDGE_NAME,
    }, {
      { success = { username = "new-bridge-api-key", clientkey = "some-client-key" } },
    })

    mock_devices_api.__expect_create_device({
      deviceNetworkId = BRIDGE_DNI,
      label = BRIDGE_NAME,
      profileReference = "hue-bridge",
      manufacturer = "Signify Netherlands B.V.",
      model = "BSB002",
      vendorProvidedLabel = BRIDGE_NAME,
      type = "LAN",
    })

    start_discovery()
    test.wait_for_events()
    stop_discovery()
    test.wait_for_events()

    assert_bridge_queried(bridge, api)
  end
)

test.register_coroutine_test(
  "with two bridges on the network, only the one that hands out an API key gets a device",
  function()
    -- Physical testing had a second, never-paired bridge on the same network; both answered
    -- discovery (recorded /api/config payloads), and only the paired one returned a key.
    local capture_payloads = require "test.fixtures.capture_payloads"
    local PAIRED_IP, UNPAIRED_IP = "192.168.1.30", "192.168.1.31"

    mock_mdns.__queue_response(Discovery.ServiceType, Discovery.Domain, {
      found = {
        mock_mdns.build_event({ name = "Hue Bridge", service_type = Discovery.ServiceType,
          domain = Discovery.Domain, address = PAIRED_IP, port = 443 }),
        mock_mdns.build_event({ name = "Hue Bridge - 2", service_type = Discovery.ServiceType,
          domain = Discovery.Domain, address = UNPAIRED_IP, port = 443 }),
      },
    })

    local paired, paired_api = bridge_at(PAIRED_IP, capture_payloads.get("bridge_config"), {
      { success = { username = "new-bridge-api-key", clientkey = "some-client-key" } },
    })
    local unpaired, unpaired_api = bridge_at(UNPAIRED_IP, capture_payloads.get("unpaired_bridge_config"), {
      { error = { type = 101, address = "", description = "link button not pressed" } },
    })

    -- The recorded paired bridge's MAC is 00:17:88:00:00:01.
    mock_devices_api.__expect_create_device({
      deviceNetworkId = "001788000001",
      label = "Hue Bridge",
      profileReference = "hue-bridge",
      manufacturer = "Signify Netherlands B.V.",
      model = "BSB002",
      vendorProvidedLabel = "Hue Bridge",
      type = "LAN",
    })

    test.socket.discovery:__queue_receive({ "start", {} })
    test.wait_for_events()
    stop_discovery()
    test.wait_for_events()

    assert_bridge_queried(paired, paired_api)
    assert_bridge_queried(unpaired, unpaired_api)
  end
)

test.run_registered_tests()
