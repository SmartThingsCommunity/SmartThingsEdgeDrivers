local test = require "integration_test"
local capabilities = require "st.capabilities"
local mock_lan_socket = require "integration_test.mock_lan_socket"
local hue_test_helpers = require "test.hue_test_helpers"
local Fields = require "fields"

-- Use proper UUID format for Hue resource IDs
local BUTTON_RID = "aaaaaaaa-bbbb-cccc-dddd-111111111111"
local BUTTON_DEVICE_ID = "aaaaaaaa-bbbb-cccc-dddd-222222222222"
local POWER_RID = "aaaaaaaa-bbbb-cccc-dddd-333333333333"

-- Single button device fixture WITH SSE enabled
local mock_bridge, mock_button, get_bridge_server, base_test_init, get_sse_connection =
  hue_test_helpers.build_paired_bridge_and_child(
    BUTTON_RID,
    {
      id = BUTTON_RID,
      hue_provided_name = "Hue Button",
      hue_device_id = BUTTON_DEVICE_ID,
      num_buttons = 1,
      button1 = {
        event_values = { "short_release", "long_press", "long_release" }
      },
      button1_id = BUTTON_RID,
      power_state = { battery_level = 85 },
      power_id = POWER_RID,
    },
    "single-button.yml",
    "button",
    function(mock_device)
      -- Register expectations for events during init lifecycle
      -- 1. supportedButtonValues from button added handler
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", 
          capabilities.button.supportedButtonValues(
            { "pushed", "held" },
            { visibility = { displayed = false } }
          )
        )
      )
      -- 2. battery event from injected refresh during init
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.battery.battery(85))
      )
    end,
    nil,  -- No device template overrides
    { enable_sse = true }  -- Enable SSE for button events
  )

test.set_test_init_function(base_test_init)

--- Identify which connection is SSE vs REST (adapted from test_hue_bridge_sse.lua)
local function identify_sse_and_rest_connections()
  test.wait_for_events()
  local labeled_conn = mock_lan_socket.tcp_registry.get_labeled(hue_test_helpers.BRIDGE_IP, 443, "sse")
  if not labeled_conn then
    -- Fallback if labeled connection doesn't exist
    return get_sse_connection(), get_bridge_server()
  end
  local sent_so_far = table.concat(labeled_conn.sent_log or {})
  if sent_so_far:match("^GET /eventstream/clip/v2 ") then
    return get_sse_connection(), get_bridge_server()
  end
  -- If the labeled connection is NOT SSE, then the order is swapped
  return get_bridge_server(), get_sse_connection()
end

--- Helper to connect SSE stream (simplified - no refresh draining yet)
local function connect_sse_for_button()
  local sse, rest = identify_sse_and_rest_connections()
  
  -- Drain the button's injected refresh REST calls (from init's _REFRESH_AFTER_INIT)
  -- Button refresh sequence (see refresh_handlers.lua + disco/button.lua):
  -- 1. GET device info (for zigbee connectivity RID)
  -- 2. GET zigbee_connectivity status
  -- 3. GET device info again (for button services)
  -- 4. GET button/{button_rid} (button details)
  -- 5. GET device_power/{power_rid} (battery)
  
  rest:queue_http_response(200, {}, {
    errors = {},
    data = { { 
      id = BUTTON_DEVICE_ID,
      services = { 
        { rtype = "zigbee_connectivity", rid = "zigbee-rid-1" },
        { rtype = "button", rid = BUTTON_RID },
        { rtype = "device_power", rid = POWER_RID }
      }
    } },
  })
  rest:queue_http_response(200, {}, {
    errors = {},
    data = { { owner = { rid = BUTTON_DEVICE_ID }, status = "connected" } },
  })
  rest:queue_http_response(200, {}, {
    errors = {},
    data = { { 
      id = BUTTON_DEVICE_ID,
      metadata = { name = "Hue Button" },
      services = { 
        { rtype = "zigbee_connectivity", rid = "zigbee-rid-1" },
        { rtype = "button", rid = BUTTON_RID },
        { rtype = "device_power", rid = POWER_RID }
      }
    } },
  })
  rest:queue_http_response(200, {}, {
    errors = {},
    data = { { 
      id = BUTTON_RID,
      type = "button",
      metadata = { control_id = 1 },
      button = {
        event_values = { "short_release", "long_press", "long_release" }
      }
    } },
  })
  rest:queue_http_response(200, {}, {
    errors = {},
    data = { { 
      id = POWER_RID,
      type = "device_power",
      power_state = { battery_level = 85 }
    } },
  })
  
  test.wait_for_events()
  rest:assert_http_request_received("GET", "/clip/v2/resource/device/" .. BUTTON_DEVICE_ID)
  rest:assert_http_request_received("GET", "/clip/v2/resource/zigbee_connectivity/zigbee-rid-1")
  rest:assert_http_request_received("GET", "/clip/v2/resource/device/" .. BUTTON_DEVICE_ID)
  rest:assert_http_request_received("GET", "/clip/v2/resource/button/" .. BUTTON_RID)
  rest:assert_http_request_received("GET", "/clip/v2/resource/device_power/" .. POWER_RID)
  
  -- Wait for and answer SSE handshake
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
  "SSE connection establishes successfully for button device",
  function()
    local sse, rest = connect_sse_for_button()
    
    -- If we got here without errors, SSE connection was established
    -- Bridge should be marked online
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "SSE short_release event emits pushed button event",
  function()
    local sse = connect_sse_for_button()
    
    test.socket.capability:__expect_send(
      mock_button:generate_test_message("main", capabilities.button.button.pushed({ state_change = true }))
    )
    
    sse:queue_sse_event({
      {
        type = "update",
        data = {
          {
            type = "button",
            id = BUTTON_RID,
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
  "SSE long_press event emits held button event",
  function()
    local sse = connect_sse_for_button()
    
    test.socket.capability:__expect_send(
      mock_button:generate_test_message("main", capabilities.button.button.held({ state_change = true }))
    )
    
    sse:queue_sse_event({
      {
        type = "update",
        data = {
          {
            type = "button",
            id = BUTTON_RID,
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
  "SSE button event with battery level emits battery event",
  function()
    local sse = connect_sse_for_button()
    
    -- Use relaxed ordering since battery and button events can arrive in any order
    test.socket.capability:__set_channel_ordering("relaxed")
    
    test.socket.capability:__expect_send(
      mock_button:generate_test_message("main", capabilities.battery.battery(42))
    )
    test.socket.capability:__expect_send(
      mock_button:generate_test_message("main", capabilities.button.button.pushed({ state_change = true }))
    )
    
    sse:queue_sse_event({
      {
        type = "update",
        data = {
          {
            type = "button",
            id = BUTTON_RID,
            power_state = {
              battery_level = 42
            },
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

test.run_registered_tests()
