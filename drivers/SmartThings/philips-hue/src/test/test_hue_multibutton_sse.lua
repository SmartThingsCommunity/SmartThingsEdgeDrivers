local test = require "integration_test"
local capabilities = require "st.capabilities"
local mock_lan_socket = require "integration_test.mock_lan_socket"
local hue_test_helpers = require "test.hue_test_helpers"
local Fields = require "fields"

-- Use proper UUID format for Hue resource IDs (4-button remote)
local BUTTON_RID_1 = "aaaaaaaa-1111-1111-1111-111111111111"
local BUTTON_RID_2 = "aaaaaaaa-2222-2222-2222-222222222222"
local BUTTON_RID_3 = "aaaaaaaa-3333-3333-3333-333333333333"
local BUTTON_RID_4 = "aaaaaaaa-4444-4444-4444-444444444444"
local BUTTON_DEVICE_ID = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
local POWER_RID = "cccccccc-cccc-cccc-cccc-cccccccccccc"

-- 4-button remote fixture WITH SSE enabled
local mock_bridge, mock_remote, get_bridge_server, base_test_init, get_sse_connection =
  hue_test_helpers.build_paired_bridge_and_child(
    BUTTON_RID_1,
    {
      id = BUTTON_RID_1,
      hue_provided_name = "Hue Dimmer Remote",
      hue_device_id = BUTTON_DEVICE_ID,
      num_buttons = 4,
      button1 = { event_values = { "short_release", "long_press" } },
      button1_id = BUTTON_RID_1,
      button2 = { event_values = { "short_release", "long_press" } },
      button2_id = BUTTON_RID_2,
      button3 = { event_values = { "short_release", "long_press" } },
      button3_id = BUTTON_RID_3,
      button4 = { event_values = { "short_release", "long_press" } },
      button4_id = BUTTON_RID_4,
      power_state = { battery_level = 90 },
      power_id = POWER_RID,
    },
    "4-button-remote.yml",
    "button",
    function(mock_device)
      -- Register expectations for events during init lifecycle
      -- supportedButtonValues for each button component
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", 
          capabilities.button.supportedButtonValues(
            { "pushed", "held" },
            { visibility = { displayed = false } }
          )
        )
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("button2", 
          capabilities.button.supportedButtonValues(
            { "pushed", "held" },
            { visibility = { displayed = false } }
          )
        )
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("button3", 
          capabilities.button.supportedButtonValues(
            { "pushed", "held" },
            { visibility = { displayed = false } }
          )
        )
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("button4", 
          capabilities.button.supportedButtonValues(
            { "pushed", "held" },
            { visibility = { displayed = false } }
          )
        )
      )
      -- Battery event from injected refresh during init
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.battery.battery(90))
      )
    end,
    nil,  -- No device template overrides
    { enable_sse = true }
  )

test.set_test_init_function(base_test_init)

--- Identify which connection is SSE vs REST
local function identify_sse_and_rest_connections()
  test.wait_for_events()
  local labeled_conn = mock_lan_socket.tcp_registry.get_labeled(hue_test_helpers.BRIDGE_IP, 443, "sse")
  if not labeled_conn then
    return get_sse_connection(), get_bridge_server()
  end
  local sent_so_far = table.concat(labeled_conn.sent_log or {})
  if sent_so_far:match("^GET /eventstream/clip/v2 ") then
    return get_sse_connection(), get_bridge_server()
  end
  return get_bridge_server(), get_sse_connection()
end

--- Helper to connect SSE stream for 4-button remote
local function connect_sse_for_multibutton()
  local sse, rest = identify_sse_and_rest_connections()
  
  -- Drain the button's injected refresh REST calls (from init's _REFRESH_AFTER_INIT)
  -- 4-button remote refresh: 1+2+3+4+5 = 8 total REST calls
  -- 1. GET device info (for zigbee connectivity RID)
  rest:queue_http_response(200, {}, {
    errors = {},
    data = { { 
      id = BUTTON_DEVICE_ID,
      services = { 
        { rtype = "zigbee_connectivity", rid = "zigbee-rid-1" },
        { rtype = "button", rid = BUTTON_RID_1 },
        { rtype = "button", rid = BUTTON_RID_2 },
        { rtype = "button", rid = BUTTON_RID_3 },
        { rtype = "button", rid = BUTTON_RID_4 },
        { rtype = "device_power", rid = POWER_RID }
      }
    } },
  })
  
  -- 2. GET zigbee_connectivity status
  rest:queue_http_response(200, {}, {
    errors = {},
    data = { { owner = { rid = BUTTON_DEVICE_ID }, status = "connected" } },
  })
  
  -- 3. GET device info again (for button services)
  rest:queue_http_response(200, {}, {
    errors = {},
    data = { { 
      id = BUTTON_DEVICE_ID,
      metadata = { name = "Hue Dimmer Remote" },
      services = { 
        { rtype = "zigbee_connectivity", rid = "zigbee-rid-1" },
        { rtype = "button", rid = BUTTON_RID_1 },
        { rtype = "button", rid = BUTTON_RID_2 },
        { rtype = "button", rid = BUTTON_RID_3 },
        { rtype = "button", rid = BUTTON_RID_4 },
        { rtype = "device_power", rid = POWER_RID }
      }
    } },
  })
  
  -- 4-7. GET button details for each button (control_id determines index)
  rest:queue_http_response(200, {}, {
    errors = {},
    data = { { 
      id = BUTTON_RID_1,
      type = "button",
      metadata = { control_id = 1 },
      button = { event_values = { "short_release", "long_press" } }
    } },
  })
  rest:queue_http_response(200, {}, {
    errors = {},
    data = { { 
      id = BUTTON_RID_2,
      type = "button",
      metadata = { control_id = 2 },
      button = { event_values = { "short_release", "long_press" } }
    } },
  })
  rest:queue_http_response(200, {}, {
    errors = {},
    data = { { 
      id = BUTTON_RID_3,
      type = "button",
      metadata = { control_id = 3 },
      button = { event_values = { "short_release", "long_press" } }
    } },
  })
  rest:queue_http_response(200, {}, {
    errors = {},
    data = { { 
      id = BUTTON_RID_4,
      type = "button",
      metadata = { control_id = 4 },
      button = { event_values = { "short_release", "long_press" } }
    } },
  })
  
  -- 8. GET device_power (battery)
  rest:queue_http_response(200, {}, {
    errors = {},
    data = { { 
      id = POWER_RID,
      type = "device_power",
      power_state = { battery_level = 90 }
    } },
  })
  
  test.wait_for_events()
  rest:assert_http_request_received("GET", "/clip/v2/resource/device/" .. BUTTON_DEVICE_ID)
  rest:assert_http_request_received("GET", "/clip/v2/resource/zigbee_connectivity/zigbee-rid-1")
  rest:assert_http_request_received("GET", "/clip/v2/resource/device/" .. BUTTON_DEVICE_ID)
  rest:assert_http_request_received("GET", "/clip/v2/resource/button/" .. BUTTON_RID_1)
  rest:assert_http_request_received("GET", "/clip/v2/resource/button/" .. BUTTON_RID_2)
  rest:assert_http_request_received("GET", "/clip/v2/resource/button/" .. BUTTON_RID_3)
  rest:assert_http_request_received("GET", "/clip/v2/resource/button/" .. BUTTON_RID_4)
  rest:assert_http_request_received("GET", "/clip/v2/resource/device_power/" .. POWER_RID)
  
  -- Answer SSE handshake
  sse:assert_http_request_received("GET", "/eventstream/clip/v2", {
    headers = { accept = "text/event-stream" },
  })
  sse:queue_sse_headers(200)
  test.wait_for_events()
  
  -- Answer onopen connectivity poll
  rest:queue_http_response(200, {}, {
    errors = {},
    data = { { owner = { rid = "unrelated-device" }, status = "connected" } },
  })
  test.wait_for_events()
  rest:assert_http_request_received("GET", "/clip/v2/resource/zigbee_connectivity")
  test.wait_for_events()
  
  return sse, rest
end

test.register_coroutine_test(
  "SSE event to button 1 (main component) routes correctly",
  function()
    local sse = connect_sse_for_multibutton()
    
    test.socket.capability:__expect_send(
      mock_remote:generate_test_message("main", capabilities.button.button.pushed({ state_change = true }))
    )
    
    sse:queue_sse_event({
      {
        type = "update",
        data = {
          {
            type = "button",
            id = BUTTON_RID_1,
            button = {
              button_report = {
                event = "short_release",
                updated = "2024-01-01T12:00:00Z"
              }
            }
          }
        },
      },
    })
    
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "SSE event to button 2 routes to button2 component",
  function()
    local sse = connect_sse_for_multibutton()
    
    test.socket.capability:__expect_send(
      mock_remote:generate_test_message("button2", capabilities.button.button.held({ state_change = true }))
    )
    
    sse:queue_sse_event({
      {
        type = "update",
        data = {
          {
            type = "button",
            id = BUTTON_RID_2,
            button = {
              button_report = {
                event = "long_press",
                updated = "2024-01-01T12:00:00Z"
              }
            }
          }
        },
      },
    })
    
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "SSE event to button 3 routes to button3 component",
  function()
    local sse = connect_sse_for_multibutton()
    
    test.socket.capability:__expect_send(
      mock_remote:generate_test_message("button3", capabilities.button.button.pushed({ state_change = true }))
    )
    
    sse:queue_sse_event({
      {
        type = "update",
        data = {
          {
            type = "button",
            id = BUTTON_RID_3,
            button = {
              button_report = {
                event = "short_release",
                updated = "2024-01-01T12:00:00Z"
              }
            }
          }
        },
      },
    })
    
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "SSE event to button 4 routes to button4 component",
  function()
    local sse = connect_sse_for_multibutton()
    
    test.socket.capability:__expect_send(
      mock_remote:generate_test_message("button4", capabilities.button.button.held({ state_change = true }))
    )
    
    sse:queue_sse_event({
      {
        type = "update",
        data = {
          {
            type = "button",
            id = BUTTON_RID_4,
            button = {
              button_report = {
                event = "long_press",
                updated = "2024-01-01T12:00:00Z"
              }
            }
          }
        },
      },
    })
    
    test.wait_for_events()
  end
)

test.run_registered_tests()
