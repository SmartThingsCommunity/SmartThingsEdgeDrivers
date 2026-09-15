--- Test for Hue button device with SSE events.
--- Uses HueDeviceBuilder and ConnectionScenario 2.0 with device-type-specific helper.

local test = require "integration_test"
local capabilities = require "st.capabilities"
local hue_test_helpers = require "test.hue_test_helpers"
local http = require "integration_test.connection_scenario_http"

-- Test constants
local BUTTON_RID = "aaaaaaaa-bbbb-cccc-dddd-111111111111"
local BUTTON_DEVICE_ID = "aaaaaaaa-bbbb-cccc-dddd-222222222222"
local POWER_RID = "aaaaaaaa-bbbb-cccc-dddd-333333333333"
local ZIGBEE_RID = "aaaaaaaa-bbbb-cccc-dddd-444444444444"

-- Create test fixture using HueDeviceBuilder
local fixtures = hue_test_helpers.HueDeviceBuilder.new()
  :with_bridge()
  :with_button(BUTTON_RID, {
    num_buttons = 1,
    battery = 85,
    label = "Hue Button",
    device_id = BUTTON_DEVICE_ID,
    power_rid = POWER_RID
  })
  :enable_sse()
  :start()

local mock_bridge, mock_button = fixtures.bridge, fixtures.devices[1]

-- Create connection scenario with REST and SSE connections
local scenario, conns = hue_test_helpers.create_hue_scenario({ sse = true })
local rest, sse = conns.rest, conns.sse

-- Setup all button init expectations using device-specific helper
-- Override zigbee_rid since the builder uses a default pattern
local button_config = fixtures.configs.button[1]
button_config.zigbee_rid = ZIGBEE_RID
hue_test_helpers.setup_button_init_expectations(rest, sse, button_config)

-- Setup test init with scenario activation
hue_test_helpers.setup_scenario_test_init(fixtures.test_init, scenario)

test.register_coroutine_test(
  "SSE connection establishes successfully for button device",
  function()
    -- If we got here without errors, SSE connection was established
    test.wait_for_events()
    
    -- Verify connections are available
    local rest_conn = scenario:get_connection("rest")
    local sse_conn = scenario:get_connection("sse")
    assert(rest_conn ~= nil, "REST connection should be available")
    assert(sse_conn ~= nil, "SSE connection should be available")
  end
)

test.register_coroutine_test(
  "SSE short_release event emits pushed button event",
  function()
    test.socket.capability:__expect_send(
      mock_button:generate_test_message("main", capabilities.button.button.pushed({ state_change = true }))
    )
    
    -- Send SSE event for short_release using helper
    local sse_conn = scenario:get_connection("sse")
    http.queue_sse_event(sse_conn, { hue_test_helpers.button_event(BUTTON_RID, "short_release") })
    
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "SSE long_press event emits held button event",
  function()
    test.socket.capability:__expect_send(
      mock_button:generate_test_message("main", capabilities.button.button.held({ state_change = true }))
    )
    
    -- Send SSE event for long_press using helper
    local sse_conn = scenario:get_connection("sse")
    http.queue_sse_event(sse_conn, { hue_test_helpers.button_event(BUTTON_RID, "long_press") })
    
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "SSE button event with battery level emits battery event",
  function()
    -- Use relaxed ordering since battery and button events can arrive in any order
    test.socket.capability:__set_channel_ordering("relaxed")
    
    test.socket.capability:__expect_send(
      mock_button:generate_test_message("main", capabilities.battery.battery(42))
    )
    test.socket.capability:__expect_send(
      mock_button:generate_test_message("main", capabilities.button.button.pushed({ state_change = true }))
    )
    
    -- Send SSE event with both button and battery data using helper
    local sse_conn = scenario:get_connection("sse")
    http.queue_sse_event(sse_conn, { hue_test_helpers.button_event(BUTTON_RID, "short_release", {
      battery_level = 42
    }) })
    
    test.wait_for_events()
  end
)

test.run_registered_tests()
