local test = require "integration_test.cosock_runner"
local testenv = require "test.testenv"

local capabilities = require "st.capabilities"
local st_utils = require "st.utils"

local Consts = require "consts"
local Discovery = require "disco"
local Fields = require "fields"
local HueDeviceTypes = require "hue_device_types"
local hue_utils = require "utils"

-- local copy of the real capability deployed for the driver.
-- loaded in to the test environment in test.testenv.lua
local syncCapabilityId = "samsungim.hueSyncMode"
local hueSyncMode = capabilities[syncCapabilityId]

test.register_coroutine_test(
  "Test Scanning Bridge Finds Child Bulb (White Ambiance Bulb)",
  function()
    local driver_under_test = test.driver_wrapper.driver_under_test

    --- tells the mocked `create_device` method to ignore assertions on this event;
    ---
    --- Without setting this, we'd have to write an assert for every
    --- device we're going to create, which would require creating the
    --- device using Mock Device APIs first, and that won't work with
    --- the flow that w're testing.
    test.mock_devices_api.assert_device_create_events(false)

    assert(testenv.mock_hue_bridge, "test init didn't create mock bridge server")

    --- This creates a mocked SmartThings device record representing the global
    --- bridge singleton we spun up in the test env.
    local mock_bridge_st_device = testenv.create_already_onboarded_bridge_device(driver_under_test)

    --- Register a device with the mock bridge such that its available via the REST API.
    --- This populates the `device`, `light`, and `zigbee_connectivity` services.
    --- The populated device template in Lua Table form is returned, as if this data
    --- was received from an API call to the Hue Bridge and deserialized.
    local mock_hue_device_service = testenv.mock_hue_bridge:add_device_from_template(
      -- device type of the primary service
      HueDeviceTypes.LIGHT,
      -- which template to load
      "test_data/templates/white-ambiance-bulb",
      -- the name override
      "Test Hue White Ambiance Bulb"
      -- and the state override table would be here if we needed to override anything
    )

    --- Generate the mock REST API server with all registered devices,
    --- and start the server thread
    testenv.mock_hue_bridge:start()
    --- Add the mock ST Device Record to the driver's device list
    test.mock_device.add_test_device(mock_bridge_st_device)

    --- Wait for device lifecycle events for the added bridge
    test.wait_for_events()

    --- Doesn't run an entire discovery loop; just runs the part
    --- of discovery that happens when a new Bridge is found. This
    --- will scan the bridge's API and create devices based on the REST
    --- results.
    Discovery.scan_bridge_and_update_devices(
      driver_under_test,
      mock_bridge_st_device.device_network_id
    )

    --- Wait for discovered devices to be added and processed; this is
    --- where the device we mocked in the REST API will be discovered and
    --- a device record will be created.
    test.wait_for_events()

    --- Now we'll write our assertions.

    --- First we get the list of devices from the driver.
    local devices = test.driver_wrapper.driver_under_test:get_devices()

    --- Look for the ST device record matching the child bulb
    --- that we registered with the REST server earlier. We know
    --- we only registered one light bulb, so we can break on the
    --- first one we find.
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
  "Test Refreshing Child Bulb Emits Events [White Ambiance Bulb: On/Off, Dimming, Color Temperature, Sync Mode]",
  function()
    local driver_under_test = test.driver_wrapper.driver_under_test

    test.mock_devices_api.assert_device_create_events(false)
    assert(testenv.mock_hue_bridge, "test init didn't create mock bridge server")

    local mock_bridge_st_device = testenv.create_already_onboarded_bridge_device(driver_under_test)
    local mock_hue_device_service = testenv.mock_hue_bridge:add_device_from_template(
      HueDeviceTypes.LIGHT,
      "test_data/templates/white-ambiance-bulb",
      "Test Hue White Ambiance Bulb"
    )
    testenv.mock_hue_bridge:start()
    test.mock_device.add_test_device(mock_bridge_st_device)
    test.wait_for_events()


    Discovery.scan_bridge_and_update_devices(
      driver_under_test,
      mock_bridge_st_device.device_network_id
    )

    test.wait_for_events()

    local devices = test.driver_wrapper.driver_under_test:get_devices()

    local light_device
    for _, device in ipairs(devices) do
      if device:get_field(Fields.DEVICE_TYPE) == HueDeviceTypes.LIGHT then
        light_device = device
        break
      end
    end

    -- Up to this point, this has all been mostly the same as the
    -- previous tests's boilerplate. Coming up is the code where we
    -- handle the lifecycle event attribute emits.

    -- First we set the channel ordering to relaxed, because
    -- we don't want to enforce ordering.
    test.socket.capability:__set_channel_ordering("relaxed")

    -- We set up capability send expectations for all of the capabilities
    -- that the profile exposes because the `added` handler will emit these attributes.

    -- We expect an `on` because the value in the template file is on, and we
    -- didn't provid an override.
    test.socket.capability:__expect_send(
      light_device:generate_test_message("main", capabilities.switch.switch.on())
    )
    -- We expect an `100` because the value in the template file is 100.
    test.socket.capability:__expect_send(
      light_device:generate_test_message("main", capabilities.switchLevel.level(100))
    )

    -- We take the mirek value that's in the test data, convert it to kelvin,
    -- and populate the expected capability emit. We don't use the device service
    -- table from above because as the name indicates, it's for the root
    -- device service and not the light service.
    local min = light_device:get_field(Fields.MIN_KELVIN) or Consts.MIN_TEMP_KELVIN_WHITE_AMBIANCE
    local kelvin = assert( math.floor(
      st_utils.clamp_value(hue_utils.mirek_to_kelvin(366), min, Consts.MAX_TEMP_KELVIN)
    ))
    local emit = assert(capabilities.colorTemperature.colorTemperature(kelvin))
    test.socket.capability:__expect_send(
      light_device:generate_test_message("main", emit)
    )

    -- We expect `"normal"` because the value in the template file is "normal".
    test.socket.capability:__expect_send(
      light_device:generate_test_message("main", hueSyncMode.mode("normal"))
    )

    -- The added lifecycle handler will invoke the refresh handler, so we wait for the expected emits
    while not light_device:get_field(Fields._ADDED) do
      test.wait_for_events()
    end
    test.wait_for_events()

    -- Repeat the above for the init handler.
    test.socket.capability:__expect_send(
      light_device:generate_test_message("main", capabilities.switch.switch.on())
    )
    test.socket.capability:__expect_send(
      light_device:generate_test_message("main", capabilities.switchLevel.level(100))
    )
    local min = light_device:get_field(Fields.MIN_KELVIN) or Consts.MIN_TEMP_KELVIN_WHITE_AMBIANCE
    local kelvin = assert( math.floor(
      st_utils.clamp_value(hue_utils.mirek_to_kelvin(366), min, Consts.MAX_TEMP_KELVIN)
    ))
    local emit = assert(capabilities.colorTemperature.colorTemperature(kelvin))
    test.socket.capability:__expect_send(
      light_device:generate_test_message("main", emit)
    )
    test.socket.capability:__expect_send(
      light_device:generate_test_message("main", hueSyncMode.mode("normal"))
    )

    while not light_device:get_field(Fields._INIT) do
      test.wait_for_events()
    end
    test.wait_for_events()

    -- We'll queue up a receive capability command to verify that the emits happen for
    -- the capability command handler as well.
    test.socket.capability:__queue_receive(
      { light_device.id,
        { capability = "refresh", component = "main", command = "refresh", args = {} }
      }
    )
    test.socket.capability:__expect_send(
      light_device:generate_test_message("main", capabilities.switch.switch.on())
    )
    test.socket.capability:__expect_send(
      light_device:generate_test_message("main", capabilities.switchLevel.level(100))
    )
    local min = light_device:get_field(Fields.MIN_KELVIN) or Consts.MIN_TEMP_KELVIN_WHITE_AMBIANCE
    local kelvin = assert( math.floor(
      st_utils.clamp_value(hue_utils.mirek_to_kelvin(366), min, Consts.MAX_TEMP_KELVIN)
    ))
    local emit = assert(capabilities.colorTemperature.colorTemperature(kelvin))
    test.socket.capability:__expect_send(
      light_device:generate_test_message("main", emit)
    )

    test.socket.capability:__expect_send(
      light_device:generate_test_message("main", hueSyncMode.mode("normal"))
    )

    test.wait_for_events()
  end,
  {}
)

test.add_test_env_setup_func(testenv.driver_env_init)
test.set_test_init_function(testenv.testenv_init)
test.set_test_cleanup_function(testenv.testenv_cleanup)
test.run_registered_tests()
