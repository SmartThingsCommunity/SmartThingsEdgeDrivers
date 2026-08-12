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
local mock_bridge, mock_remote, get_bridge_server, base_test_init, get_sse_connection =
  hue_test_helpers.HueDeviceBuilder.new()
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

-- Set up ConnectionScenario for this host:port
local scenario, conns = hue_test_helpers.create_hue_scenario({ sse = true })
local rest, sse = conns.rest, conns.sse

-- Setup test init with scenario activation
hue_test_helpers.setup_scenario_test_init(base_test_init, scenario)

-- 1. GET device info (reusable: may be called multiple times during refresh)
hue_test_helpers.expect_device_info(rest, BUTTON_DEVICE_ID, {
  { rtype = "zigbee_connectivity", rid = ZIGBEE_RID },
  { rtype = "button", rid = BUTTON_RID_1 },
  { rtype = "button", rid = BUTTON_RID_2 },
  { rtype = "button", rid = BUTTON_RID_3 },
  { rtype = "button", rid = BUTTON_RID_4 },
  { rtype = "device_power", rid = POWER_RID },
}, {
  name = "Hue Dimmer Remote",
  product_data = { product_name = "Hue Dimmer Remote" },
  reusable = true
})

-- 2. GET zigbee connectivity
hue_test_helpers.expect_zigbee_connectivity(rest, ZIGBEE_RID)

-- 3-6. GET button info for all 4 buttons
hue_test_helpers.expect_button_resource(rest, BUTTON_RID_1, { control_id = 1 })
hue_test_helpers.expect_button_resource(rest, BUTTON_RID_2, { control_id = 2 })
hue_test_helpers.expect_button_resource(rest, BUTTON_RID_3, { control_id = 3 })
hue_test_helpers.expect_button_resource(rest, BUTTON_RID_4, { control_id = 4 })

-- 7. GET device power
hue_test_helpers.expect_device_power(rest, POWER_RID, 90)

-- 8. SSE handshake and connectivity poll
hue_test_helpers.setup_sse_expectations(sse, rest)

-- 9. Room resource query (reusable)
http.expect_request(rest, "GET", "/clip/v2/resource/room", {
  status = 200,
  body = { errors = {}, data = {} },
  reusable = true
})

-- 10. Zone resource query (reusable)
http.expect_request(rest, "GET", "/clip/v2/resource/zone", {
  status = 200,
  body = { errors = {}, data = {} },
  reusable = true
})

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
