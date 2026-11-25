-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- From discovery to a working light, end to end: mDNS finds a bridge and the driver pairs with it
--- and creates its device; the hub adds the bridge, which connects its event stream; discovery then
--- finds a colour lamp on the bridge and creates its device; the hub adds the lamp, which reads its
--- state; and the lamp then takes a command and reports the bridge's state update. Nothing is
--- pre-populated: every step runs for real against the mock bridge (payloads recorded on real
--- hardware, see test/fixtures/capture_payloads.lua).

-- These tests use the integration test framework's LAN support, new in lua_libs API version 23.
-- With older lua_libs, skip the file rather than fail loading it.
if require("version").api < 23 then return end

local test = require "integration_test"
local hue_test_helpers = require "test.hue_test_helpers"
local http = require "integration_test.connection_scenario_http"
local capture_payloads = require "test.fixtures.capture_payloads"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"

local Discovery = require "disco"

local ids = capture_payloads.ids

local BRIDGE_IP = "192.168.1.40"
-- The recorded bridge config's MAC, 00:17:88:00:00:01, with the separators stripped.
local BRIDGE_DNI = "001788000001"
local LAMP_PROFILE = "white-and-color-ambiance"

test.add_test_env_setup_func(function(driver)
  -- disco is a module-level singleton that persists across tests within this file.
  Discovery.discovery_active = false
  Discovery.api_keys = {}
  Discovery.disco_api_instances = {}
end)

local scenario, conns = hue_test_helpers.create_hue_scenario({ host = BRIDGE_IP })
local rest, sse = conns.rest, conns.sse
-- Discovery's requests: the bridge's config, and an API key once the Link Button is pressed.
local api = scenario:connection("api", { matcher = http.matcher({ "GET", "POST" }, "^/api"), ordering = "relaxed" })
http.expect_request(api, "GET", "/api/config", { body = capture_payloads.get("bridge_config"), reusable = true })
http.expect_request(api, "POST", "/api", {
  body = { { success = { username = "new-bridge-api-key", clientkey = "some-client-key" } } },
  reusable = true,
})

http.expect_sse_handshake(sse, "/eventstream/clip/v2", true)

-- The bridge has one device, the recorded colour lamp.
local lamp_device = capture_payloads.get("color_lamp_device").data[1]
local lamp_zigbee = capture_payloads.get("color_lamp_zigbee").data[1]
http.expect_request(rest, "GET", "/clip/v2/resource/device", {
  body = { errors = {}, data = { lamp_device } }, reusable = true,
})
http.expect_request(rest, "GET", "/clip/v2/resource/device/" .. ids.color_lamp_device, {
  body = capture_payloads.get("color_lamp_device"), reusable = true,
})
http.expect_request(rest, "GET", "/clip/v2/resource/light/" .. ids.color_lamp_light, {
  body = capture_payloads.get("color_lamp_light"), reusable = true,
})
http.expect_request(rest, "GET", "/clip/v2/resource/zigbee_connectivity", {
  body = { errors = {}, data = { lamp_zigbee } }, reusable = true,
})
http.expect_request(rest, "GET", "/clip/v2/resource/zigbee_connectivity/" .. ids.color_lamp_zigbee, {
  body = capture_payloads.get("color_lamp_zigbee"), reusable = true,
})

test.set_test_init_function(function()
  scenario:activate()
end)

--- What the lamp reports when it reads its state from the bridge: once from `added` and again
--- from `init` (when only the colour temperature range, being unchanged, isn't sent again).
local function expect_lamp_state_events(lamp_mock, with_range)
  local function expect(event)
    test.socket.capability:__expect_send(lamp_mock:generate_test_message("main", event))
  end
  expect(capabilities["samsungim.hueSyncMode"].mode("normal"))
  expect(capabilities.switch.switch.on())
  expect(capabilities.switchLevel.level(100))
  if with_range then
    expect(capabilities.colorTemperature.colorTemperatureRange({ minimum = 2000, maximum = 6500 }))
  end
  -- The recorded state: 366 mirek, and xy (0.4572, 0.4099) in gamut C.
  expect(capabilities.colorTemperature.colorTemperature(2732))
  expect(capabilities.colorControl.hue(11))
  expect(capabilities.colorControl.saturation(53))
end

local function start_discovery()
  test.mock_mdns.__queue_response(Discovery.ServiceType, Discovery.Domain, {
    found = {
      test.mock_mdns.build_event({
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

test.register_coroutine_test(
  "a discovered bridge and the lamp found on it are created, set up, and the lamp then works",
  function()
    test.socket.capability:__set_channel_ordering("relaxed")

    local lamp
    local bridge = test.mock_devices_api.__expect_create_device({
      type = "LAN",
      deviceNetworkId = BRIDGE_DNI,
      label = "Hue Bridge",
      profileReference = "hue-bridge",
      manufacturer = "Signify Netherlands B.V.",
      model = "BSB002",
      vendorProvidedLabel = "Hue Bridge",
    }, {
      adopt = {
        profile = t_utils.get_profile_definition("hue-bridge.yml"),
        -- Once the bridge exists, the lamp discovery finds on it is created as its child.
        on_created = function(bridge_device)
          lamp = test.mock_devices_api.__expect_create_device({
            type = "EDGE_CHILD",
            label = "Hue color lamp 1",
            profileReference = LAMP_PROFILE,
            parentDeviceId = bridge_device.id,
            manufacturer = "Signify Netherlands B.V.",
            model = "LCT014",
            parentAssignedChildKey = "light:" .. ids.color_lamp_light,
          }, {
            adopt = {
              profile = t_utils.get_profile_definition(LAMP_PROFILE .. ".yml"),
              on_created = function(lamp_mock)
                expect_lamp_state_events(lamp_mock, true)  -- added
                hue_test_helpers.expect_light_init_events(lamp_mock, LAMP_PROFILE .. ".yml")
                expect_lamp_state_events(lamp_mock, false)  -- init
              end,
            },
          })
        end,
      },
    })

    -- Discovery pairs with the bridge on its first pass and finds the lamp on a later one.
    start_discovery()
    test.wait_until(function() return lamp ~= nil and lamp.device ~= nil end,
      { within = 30, message = "the bridge and then the lamp being created" })
    test.socket.discovery:__queue_receive({ "stop" })
    test.wait_until(function()
      return test.mock_devices_api.__is_device_online(bridge.device.id) == true
    end, { within = 30, message = "the bridge's event stream connecting" })
    -- Let the lamp finish setting up (the batched capability receive delivers its state events).
    test.wait_for_events()
    assert(http.count_requests(rest, "GET", "/clip/v2/resource/light/" .. ids.color_lamp_light) >= 1,
      "expected the lamp to read its state from the bridge")

    -- The lamp works: a command reaches the bridge, and the bridge's state update reaches the lamp.
    local lamp_device = lamp.device
    test.socket.capability:__set_channel_ordering("strict")
    http.expect_request(rest, "PUT", "/clip/v2/resource/light/" .. ids.color_lamp_light, {
      request_json = { on = { on = false } },
      body = { errors = {}, data = { { rid = ids.color_lamp_light, rtype = "light" } } },
    })
    test.socket.capability:__queue_receive({
      lamp_device.id, { capability = "switch", component = "main", command = "off", args = {} },
    })
    test.wait_for_events()
    http.queue_sse_event(sse, { hue_test_helpers.light_event(ids.color_lamp_light, false) })
    test.socket.capability:__expect_send(lamp_device:generate_test_message("main", capabilities.switch.switch.off()))
    test.wait_for_events()
  end,
  { min_api_version = 23 }
)

test.run_registered_tests()
