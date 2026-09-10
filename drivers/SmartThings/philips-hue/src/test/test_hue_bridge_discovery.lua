local test = require "integration_test"
local lan_test_utils = require "integration_test.lan_test_utils"
local mock_mdns = require "integration_test.mock_mdns"
local mock_devices_api = require "integration_test.mock_devices_api"

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
  -- these tests exercise.
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

test.register_coroutine_test(
  "mDNS discovery finds a bridge and requests an API key, but does not create a device if the Link Button hasn't been pressed",
  function()
    local bridge_server = lan_test_utils.build_mock_server(BRIDGE_IP, 443)
    bridge_server:queue_http_response(200, {}, {
      mac = BRIDGE_MAC,
      swversion = "1968054000",
      modelid = "BSB002",
      name = BRIDGE_NAME,
    })
    bridge_server:queue_http_response(200, {}, {
      { error = { type = 101, address = "/", description = "link button not pressed" } },
    })

    start_discovery()
    test.wait_for_events()
    stop_discovery()
    test.wait_for_events()

    bridge_server:assert_http_request_received("GET", "/api/config")
    bridge_server:assert_http_request_received(
      "POST",
      "/api",
      { body = { devicetype = "smartthings_edge_driver#" .. BRIDGE_IP, generateclientkey = true } }
    )
  end
)

test.register_coroutine_test(
  "mDNS discovery creates a bridge device once an API key is obtained",
  function()
    local bridge_server = lan_test_utils.build_mock_server(BRIDGE_IP, 443)
    bridge_server:queue_http_response(200, {}, {
      mac = BRIDGE_MAC,
      swversion = "1968054000",
      modelid = "BSB002",
      name = BRIDGE_NAME,
    })
    bridge_server:queue_http_response(200, {}, {
      { success = { username = "new-bridge-api-key", client_key = "some-client-key" } },
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

    bridge_server:assert_http_request_received("GET", "/api/config")
    bridge_server:assert_http_request_received(
      "POST",
      "/api",
      { body = { devicetype = "smartthings_edge_driver#" .. BRIDGE_IP, generateclientkey = true } }
    )
  end
)

test.run_registered_tests()
