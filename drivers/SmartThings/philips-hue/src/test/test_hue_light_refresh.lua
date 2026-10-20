-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- A refresh command reads the light's state from the bridge and emits it.

local test = require "integration_test"
local capabilities = require "st.capabilities"
local hue_test_helpers = require "test.hue_test_helpers"

local LIGHT_RID = "22222222-2222-2222-2222-222222222222"
local HUE_DEVICE_ID = "device-uuid-1"
local ZIGBEE_RID = "zigbee-conn-1"

local fixtures = hue_test_helpers.HueDeviceBuilder.new()
  :with_bridge()
  :with_light(LIGHT_RID, {
    on = { on = true },
    dimming = { brightness = 80 },
    hue_device_id = HUE_DEVICE_ID,
    zigbee_rid = ZIGBEE_RID,
  }, "white-and-color-ambiance.yml")
  :expect_light_init_refreshes()
  :start()

local mock_bridge, mock_light = fixtures.bridge, fixtures.devices[1]

local scenario, conns = hue_test_helpers.create_hue_scenario()
local rest, sse = conns.rest, conns.sse

-- The light's init refreshes and the event stream. A refresh queries the light's device (to find
-- its zigbee_connectivity resource), then its connectivity, then its state; the device and
-- connectivity expectations are reusable, so they answer the tests' refreshes too.
hue_test_helpers.setup_light_init_expectations(rest, fixtures.configs.light[1])
hue_test_helpers.setup_sse_expectations(sse, rest)

hue_test_helpers.setup_scenario_test_init(fixtures.test_init, scenario)

local function refresh_with_light_state(on, brightness)
  hue_test_helpers.wait_for_init(scenario, mock_bridge)
  hue_test_helpers.expect_resource(rest, "light", LIGHT_RID, {
    owner = { rid = HUE_DEVICE_ID, rtype = "device" },
    on = { on = on },
    dimming = { brightness = brightness },
  })

  test.socket.capability:__queue_receive({
    mock_light.id,
    { capability = "refresh", component = "main", command = "refresh", args = {} },
  })
end

test.register_coroutine_test(
  "refresh command reads light state over REST and emits switch/switchLevel events",
  function()
    refresh_with_light_state(true, 60)
    test.socket.capability:__expect_send(
      mock_light:generate_test_message("main", capabilities.switch.switch.on())
    )
    test.socket.capability:__expect_send(
      mock_light:generate_test_message("main", capabilities.switchLevel.level(60))
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "refresh command reflects an off/dimmed state from the REST response",
  function()
    refresh_with_light_state(false, 15)
    test.socket.capability:__expect_send(
      mock_light:generate_test_message("main", capabilities.switch.switch.off())
    )
    test.socket.capability:__expect_send(
      mock_light:generate_test_message("main", capabilities.switchLevel.level(15))
    )
    test.wait_for_events()
  end
)

test.run_registered_tests()
