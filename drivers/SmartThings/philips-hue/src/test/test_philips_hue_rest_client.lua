local test = require "integration_test.cosock_runner"

local helpers = require "test.helpers"
local testenv = require "test.testenv"

local capabilities = require "st.capabilities"

local Discovery = require "disco"
local Fields = require "fields"
local HueApi = require "hue.api"
local HueDeviceTypes = require "hue_device_types"

local hue_utils = require "utils"

local mock_socket_builder = helpers.socket.mock_labeled_socket_builder

local HUE_BRIDGE_PORT = 443

test.add_package_capability("hueSyncMode.yml")
local syncCapabilityId = "samsungim.hueSyncMode"
local hueSyncMode = capabilities[syncCapabilityId]

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

test.register_coroutine_test(
  "Test Scanning Bridge Finds Child Bulb",
  function()
    local driver_under_test = test.driver_wrapper.driver_under_test
    --- tells the mocked `create_device` method to create a mock device
    test.mock_devices_api.assert_device_create_events(false)

    assert(testenv.mock_hue_bridge, "test init didn't create mock bridge server")

    --- create a mock device for a bridge that's already been fully onboarded (added and init will noop)
    --- TODO: mock SSE Stream support
    local mock_bridge_st_device = testenv.create_already_onboarded_bridge_device(driver_under_test)

    --- Register a device with the mock bridge such that its available via the REST API.
    --- This populates the `device`, `light`, and `zigbee_connectivity` services.
    local mock_hue_device_service = testenv.mock_hue_bridge:add_device_from_template(
      HueDeviceTypes.LIGHT,
      "test_data/templates/white-bulb"
    )

    --- Generate the mock REST API server with all registered devices
    testenv.mock_hue_bridge:start()
    --- Add the mock ST Device Record to the driver's device list
    test.mock_device.add_test_device(mock_bridge_st_device)

    --- Wait for device lifecycle events
    test.wait_for_events()

    --- Doesn't run an entire discovery loop; just runs the part
    --- of discovery that happens when a new Bridge is found. This
    --- will scan the bridge's API and create devices based on the REST
    --- results.
    Discovery.scan_bridge_and_update_devices(
      driver_under_test,
      mock_bridge_st_device.device_network_id
    )

    --- Wait for discovered devices to be added and processed
    test.wait_for_events()

    local devices = test.driver_wrapper.driver_under_test:get_devices()

    --- Look for the ST device record matching the child bulb
    --- that we registered with the REST server earlier
    local light_device
    for _, device in ipairs(devices) do
      if device:get_field(Fields.DEVICE_TYPE) == HueDeviceTypes.LIGHT then
        light_device = device
        break
      end
    end

    --- Look for the light's Hue Resource ID in the data that was generated
    --- when we loaded the template for registering with the REST server
    local light_rid
    for _, svc in ipairs(mock_hue_device_service.services) do
      if svc.rtype == HueDeviceTypes.LIGHT then
        light_rid = svc.rid
        break
      end
    end

    --- Assert that we found the device
    assert(light_device)
    --- Assert that it's correctly parented to the mock bridge device record
    assert(light_device.parent_device_id == mock_bridge_st_device.id)
    --- Assert that the derived hue resource ID based on device record properties
    --- matches the device resource ID we populated the REST server with.
    assert(hue_utils.get_hue_rid(light_device) == light_rid,
      tostring(hue_utils.get_hue_rid(light_device)) .. " ~= " .. light_rid)
  end,
  {}
)

test.register_coroutine_test(
  "Test Refreshing Child White Bulb Emits On/Off and Dimming",
  function()
    local driver_under_test = test.driver_wrapper.driver_under_test
    --- tells the mocked `create_device` method to create a mock device
    test.mock_devices_api.assert_device_create_events(false)

    assert(testenv.mock_hue_bridge, "test init didn't create mock bridge server")

    --- create a mock device for a bridge that's already been fully onboarded (added and init will noop)
    --- TODO: mock SSE Stream support
    local mock_bridge_st_device = testenv.create_already_onboarded_bridge_device(driver_under_test)

    --- Register a device with the mock bridge such that its available via the REST API.
    --- This populates the `device`, `light`, and `zigbee_connectivity` services.
    local _mock_hue_device_service = testenv.mock_hue_bridge:add_device_from_template(
      HueDeviceTypes.LIGHT,
      "test_data/templates/white-bulb"
    )

    --- Generate the mock REST API server with all registered devices
    testenv.mock_hue_bridge:start()
    --- Add the mock ST Device Record to the driver's device list
    test.mock_device.add_test_device(mock_bridge_st_device)

    --- Wait for device lifecycle events
    test.wait_for_events()

    --- Doesn't run an entire discovery loop; just runs the part
    --- of discovery that happens when a new Bridge is found. This
    --- will scan the bridge's API and create devices based on the REST
    --- results.
    Discovery.scan_bridge_and_update_devices(
      driver_under_test,
      mock_bridge_st_device.device_network_id
    )

    --- Wait for discovered devices to be added and processed
    test.wait_for_events()

    local devices = test.driver_wrapper.driver_under_test:get_devices()

    --- Look for the ST device record matching the child bulb
    --- that we registered with the REST server earlier
    local light_device
    for _, device in ipairs(devices) do
      if device:get_field(Fields.DEVICE_TYPE) == HueDeviceTypes.LIGHT then
        light_device = device
        break
      end
    end

    test.socket.capability:__set_channel_ordering("relaxed")

    -- We expect an `on` because the value in the template file is on.
    test.socket.capability:__expect_send(
      light_device:generate_test_message("main", capabilities.switch.switch.on())
    )
    -- We expect an `100` because the value in the template file is 100.
    test.socket.capability:__expect_send(
      light_device:generate_test_message("main", capabilities.switchLevel.level(100))
    )

    -- We expect `"normal"` because the value in the template file is "normal".
    test.socket.capability:__expect_send(
      light_device:generate_test_message("main", hueSyncMode.mode("normal"))
    )

    while not light_device:get_field(Fields._ADDED) do
      test.wait_for_events()
    end

    -- We expect an `on` because the value in the template file is on.
    test.socket.capability:__expect_send(
      light_device:generate_test_message("main", capabilities.switch.switch.on())
    )
    -- We expect an `100` because the value in the template file is 100.
    test.socket.capability:__expect_send(
      light_device:generate_test_message("main", capabilities.switchLevel.level(100))
    )

    -- We expect `"normal"` because the value in the template file is "normal".
    test.socket.capability:__expect_send(
      light_device:generate_test_message("main", hueSyncMode.mode("normal"))
    )

    while not light_device:get_field(Fields._INIT) do
      test.wait_for_events()
    end

    -- We expect an `on` because the value in the template file is on.
    test.socket.capability:__expect_send(
      light_device:generate_test_message("main", capabilities.switch.switch.on())
    )
    -- We expect an `100` because the value in the template file is 100.
    test.socket.capability:__expect_send(
      light_device:generate_test_message("main", capabilities.switchLevel.level(100))
    )

    -- We expect `"normal"` because the value in the template file is "normal".
    test.socket.capability:__expect_send(
      light_device:generate_test_message("main", hueSyncMode.mode("normal"))
    )

    test.socket.capability:__queue_receive(
      { light_device.id,
        { capability = "refresh", component = "main", command = "refresh", args = {} }
      }
    )

    test.wait_for_events()
  end,
  {}
)

test.add_test_env_setup_func(testenv.driver_env_init)
test.set_test_init_function(testenv.testenv_init)
test.set_test_cleanup_function(testenv.testenv_cleanup)
test.run_registered_tests()
