local test = require "integration_test"
local capabilities = require "st.capabilities"
local hue_test_helpers = require "test.hue_test_helpers"
local http = require "integration_test.connection_scenario_http"

-- Use proper UUID format for Hue resource IDs (4-button remote)
local BUTTON_RID_1 = "aaaaaaaa-1111-1111-1111-111111111111"
local BUTTON_RID_2 = "aaaaaaaa-2222-2222-2222-222222222222"
local BUTTON_RID_3 = "aaaaaaaa-3333-3333-3333-333333333333"
local BUTTON_RID_4 = "aaaaaaaa-4444-4444-4444-444444444444"
local BUTTON_DEVICE_ID = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
local POWER_RID = "cccccccc-cccc-cccc-cccc-cccccccccccc"
local ZIGBEE_RID = "zigbee-rid-1"

-- 4-button remote fixture WITH SSE enabled
local fixtures = hue_test_helpers.HueDeviceBuilder.new()
  :with_bridge()
  :with_button(BUTTON_RID_1, {
    num_buttons = 4,
    battery = 90,
    device_id = BUTTON_DEVICE_ID,
    power_rid = POWER_RID,
    button_rids = { BUTTON_RID_1, BUTTON_RID_2, BUTTON_RID_3, BUTTON_RID_4 },
    label = "Hue Dimmer Remote",
  }, "4-button-remote.yml")
  :enable_sse()
  :start()

local mock_bridge, mock_remote = fixtures.bridge, fixtures.devices[1]

-- Set up ConnectionScenario for this host:port
local scenario, conns = hue_test_helpers.create_hue_scenario({ sse = true })
local rest, sse = conns.rest, conns.sse

-- Setup all button init expectations using device-specific helper
local button_config = fixtures.configs.button[1]
button_config.zigbee_rid = ZIGBEE_RID
hue_test_helpers.setup_button_init_expectations(rest, sse, button_config)

-- Setup test init with scenario activation
hue_test_helpers.setup_scenario_test_init(fixtures.test_init, scenario)

test.register_coroutine_test(
  "SSE event to button 1 (main component) routes correctly",
  function()
    test.socket.capability:__expect_send(
      mock_remote:generate_test_message("main", capabilities.button.button.pushed({ state_change = true }))
    )
    
    http.queue_sse_event(sse, { hue_test_helpers.button_event(BUTTON_RID_1, "short_release") })
    
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "SSE event to button 2 routes to button2 component",
  function()
    test.socket.capability:__expect_send(
      mock_remote:generate_test_message("button2", capabilities.button.button.held({ state_change = true }))
    )
    
    http.queue_sse_event(sse, { hue_test_helpers.button_event(BUTTON_RID_2, "long_press") })
    
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "SSE event to button 3 routes to button3 component",
  function()
    test.socket.capability:__expect_send(
      mock_remote:generate_test_message("button3", capabilities.button.button.pushed({ state_change = true }))
    )
    
    http.queue_sse_event(sse, { hue_test_helpers.button_event(BUTTON_RID_3, "short_release") })
    
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "SSE event to button 4 routes to button4 component",
  function()
    test.socket.capability:__expect_send(
      mock_remote:generate_test_message("button4", capabilities.button.button.held({ state_change = true }))
    )
    
    http.queue_sse_event(sse, { hue_test_helpers.button_event(BUTTON_RID_4, "long_press") })
    
    test.wait_for_events()
  end
)

test.run_registered_tests()
