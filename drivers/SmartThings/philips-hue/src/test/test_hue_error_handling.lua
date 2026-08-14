local test = require "integration_test"
local capabilities = require "st.capabilities"
local hue_test_helpers = require "test.hue_test_helpers"
local Fields = require "fields"

local LIGHT_RID = "11111111-1111-1111-1111-111111111111"
local LIGHT_DEVICE_ID = "22222222-2222-2222-2222-222222222222"

-- Standard light fixture (no SSE for command tests)
local mock_bridge, mock_light, get_bridge_server, test_init, get_sse_connection =
  hue_test_helpers.build_paired_bridge_and_light(
    LIGHT_RID,
    {
      on = { on = true },
      dimming = { brightness = 100 },
      hue_device_id = LIGHT_DEVICE_ID,
    },
    "white-and-color-ambiance.yml",
    nil,
    { enable_sse = false }
  )

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Light command handles 404 error gracefully",
  function()
    -- Send switch on command
    test.socket.capability:__queue_receive({
      mock_light.id,
      { capability = "switch", component = "main", command = "on", args = {} },
    })
    
    -- Bridge returns 404 (light not found)
    get_bridge_server():queue_http_response(404, {}, {
      errors = {
        {
          type = "resource_not_found",
          description = "Resource not found"
        }
      }
    })
    
    test.wait_for_events()
    get_bridge_server():assert_http_request_received("PUT", "/clip/v2/resource/light/" .. LIGHT_RID)
    
    -- Device should not emit any state change events on error
    -- (test passes if no unexpected capability events were sent)
  end
)

test.register_coroutine_test(
  "Light command handles 500 internal server error",
  function()
    test.socket.capability:__queue_receive({
      mock_light.id,
      { capability = "switchLevel", component = "main", command = "setLevel", args = { 50 } },
    })
    
    -- Bridge returns 500 internal error
    get_bridge_server():queue_http_response(500, {}, {
      errors = {
        {
          type = "internal_error",
          description = "Internal server error"
        }
      }
    })
    
    test.wait_for_events()
    get_bridge_server():assert_http_request_received("PUT", "/clip/v2/resource/light/" .. LIGHT_RID)
    
    -- Device should not emit state change on error
  end
)

test.register_coroutine_test(
  "Light command handles Hue API error in response body",
  function()
    test.socket.capability:__queue_receive({
      mock_light.id,
      { capability = "switch", component = "main", command = "off", args = {} },
    })
    
    -- Bridge returns 200 but with errors in the response body
    get_bridge_server():queue_http_response(200, {}, {
      errors = {
        {
          description = "Light is unreachable"
        }
      },
      data = {}
    })
    
    test.wait_for_events()
    get_bridge_server():assert_http_request_received("PUT", "/clip/v2/resource/light/" .. LIGHT_RID)
    
    -- Command should handle error gracefully (no crash, logs error)
  end
)

test.register_coroutine_test(
  "Light command handles connection timeout",
  function()
    test.socket.capability:__queue_receive({
      mock_light.id,
      { capability = "switch", component = "main", command = "on", args = {} },
    })
    
    -- Simulate timeout by closing connection without response
    get_bridge_server():close_connection()
    
    test.wait_for_events()
    
    -- Driver should handle timeout gracefully without crashing
  end
)

test.register_coroutine_test(
  "Refresh handles missing zigbee connectivity gracefully",
  function()
    hue_test_helpers.mark_bridge_initialized(mock_bridge)
    test.socket.capability:__queue_receive({
      mock_light.id,
      { capability = "refresh", component = "main", command = "refresh", args = {} },
    })
    
    -- Return device info without zigbee_connectivity service
    get_bridge_server():queue_http_response(200, {}, {
      errors = {},
      data = {
        {
          id = LIGHT_DEVICE_ID,
          services = {
            { rtype = "light", rid = LIGHT_RID }
            -- Note: no zigbee_connectivity service
          }
        }
      }
    })
    
    test.wait_for_events()
    get_bridge_server():assert_http_request_received("GET", "/clip/v2/resource/device/" .. LIGHT_DEVICE_ID)
    
    -- Driver logs error about missing zigbee_connectivity and returns early
    -- (no light state fetch attempted, which is the correct behavior)
    -- Test passes if driver handles this gracefully without crashing
  end
)

test.register_coroutine_test(
  "Refresh handles 404 for deleted device",
  function()
    hue_test_helpers.mark_bridge_initialized(mock_bridge)
    test.socket.capability:__queue_receive({
      mock_light.id,
      { capability = "refresh", component = "main", command = "refresh", args = {} },
    })
    
    -- Device info lookup returns 404 (device deleted on bridge)
    get_bridge_server():queue_http_response(404, {}, {
      errors = {
        {
          type = "resource_not_found",
          description = "Device not found"
        }
      }
    })
    
    test.wait_for_events()
    get_bridge_server():assert_http_request_received("GET", "/clip/v2/resource/device/" .. LIGHT_DEVICE_ID)
    
    -- Should handle gracefully (logs error, doesn't crash)
  end
)

test.register_coroutine_test(
  "Malformed JSON response handled gracefully",
  function()
    test.socket.capability:__queue_receive({
      mock_light.id,
      { capability = "switch", component = "main", command = "on", args = {} },
    })
    
    -- Return invalid JSON (this simulates a bridge malfunction)
    get_bridge_server():queue_http_response(200, {}, "{ invalid json")
    
    test.wait_for_events()
    get_bridge_server():assert_http_request_received("PUT", "/clip/v2/resource/light/" .. LIGHT_RID)
    
    -- Driver should handle parse error without crashing
  end
)

test.register_coroutine_test(
  "Empty response body handled gracefully",
  function()
    test.socket.capability:__queue_receive({
      mock_light.id,
      { capability = "switchLevel", component = "main", command = "setLevel", args = { 25 } },
    })
    
    -- Return 200 with empty body
    get_bridge_server():queue_http_response(200, {}, "")
    
    test.wait_for_events()
    get_bridge_server():assert_http_request_received("PUT", "/clip/v2/resource/light/" .. LIGHT_RID)
    
    -- Driver should handle empty response without crashing
  end
)

test.run_registered_tests()
