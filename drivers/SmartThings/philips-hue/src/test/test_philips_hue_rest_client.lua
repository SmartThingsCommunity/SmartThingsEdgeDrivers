local test = require "integration_test.cosock_runner"

local helpers = require "test.helpers"
local testenv = require "test.testenv"

local HueApi = require "hue.api"

local mock_socket_builder = helpers.socket.mock_labeled_socket_builder

local HUE_BRIDGE_PORT = 443

-- basically a unit test, but validates the mock Hue Bridge REST API server is working
test.register_coroutine_test(
  "Test Unauthenticated Hue Bridge API Endpoint",
  function()
    assert(testenv.mock_hue_bridge, "test init didn't create mock bridge server")
    testenv.mock_hue_bridge:start()

    local mock_bridge_info = testenv.mock_hue_bridge.bridge_info
    assert(mock_bridge_info, "mock server doesn't have bridge info")

    test.socket.tcp.__expect_client_socket(mock_bridge_info.ip, HUE_BRIDGE_PORT)

    local bridge_info = assert(
      HueApi.get_bridge_info(mock_bridge_info.ip, mock_socket_builder("Mock Hue Client"))
    )
    helpers.hue_bridge.assert_bridge_info(mock_bridge_info, bridge_info)
  end,
  {}
)

test.add_test_env_setup_func(testenv.driver_env_init)
test.set_test_init_function(testenv.testenv_init)
test.set_test_cleanup_function(testenv.testenv_cleanup)
test.run_registered_tests()
