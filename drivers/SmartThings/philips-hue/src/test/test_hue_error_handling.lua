--- Test for error handling in Hue light commands and refresh operations.
--- Migrated to use connection_scenario 2.0.
---
--- Tests various error scenarios: 404, 500, API errors, timeouts, malformed JSON, etc.

local test = require "integration_test"
local capabilities = require "st.capabilities"
local hue_test_helpers = require "test.hue_test_helpers"
local connection_scenario = require "integration_test.connection_scenario"
local http = require "integration_test.connection_scenario_http"
local Fields = require "fields"

local LIGHT_RID = "11111111-1111-1111-1111-111111111111"
local LIGHT_DEVICE_ID = "22222222-2222-2222-2222-222222222222"

-- Standard light fixture (no SSE for command tests)
local mock_bridge, mock_light, get_bridge_server, base_test_init =
  hue_test_helpers.HueDeviceBuilder.new()
    :with_bridge()
    :with_light(LIGHT_RID, {
      on = { on = true },
      dimming = { brightness = 100 },
      hue_device_id = LIGHT_DEVICE_ID,
    }, "white-and-color-ambiance.yml")
    :start()

-- Set up ConnectionScenario for error handling testing
-- This test file needs both GET and PUT connections simultaneously for different test scenarios
local scenario = connection_scenario.new({ host = hue_test_helpers.BRIDGE_IP, port = 443 })

-- Define PUT connection for light commands
local put_conn = scenario:connection("put", {
  matcher = http.matcher("PUT", "/clip/v2/resource/"),
  ordering = "relaxed"
})

-- Define GET connection for refresh operations
local get_conn = scenario:connection("get", {
  matcher = http.matcher("GET", "/clip/v2/resource/"),
  ordering = "relaxed"
})

-- Setup test init with scenario activation
hue_test_helpers.setup_scenario_test_init(base_test_init, scenario)

test.register_coroutine_test(
  "Light command handles 404 error gracefully",
  function()
    -- Test-specific expectation: 404 error response
    http.expect_request_for_test(put_conn, "PUT", "/clip/v2/resource/light/" .. LIGHT_RID, {
      status = 404,
      body = {
        errors = {
          {
            type = "resource_not_found",
            description = "Resource not found"
          }
        }
      }
    })
    
    -- Send switch on command
    test.socket.capability:__queue_receive({
      mock_light.id,
      { capability = "switch", component = "main", command = "on", args = {} },
    })
    
    test.wait_for_events()
    
    -- Verify PUT request was sent
    put_conn:assert_sent("PUT /clip/v2/resource/light/11111111%-1111%-1111%-1111%-111111111111")
    
    -- Device should not emit any state change events on error
    -- (test passes if no unexpected capability events were sent)
  end
)

test.register_coroutine_test(
  "Light command handles 500 internal server error",
  function()
    http.expect_request_for_test(put_conn, "PUT", "/clip/v2/resource/light/" .. LIGHT_RID, {
      status = 500,
      body = {
        errors = {
          {
            type = "internal_error",
            description = "Internal server error"
          }
        }
      }
    })
    
    test.socket.capability:__queue_receive({
      mock_light.id,
      { capability = "switchLevel", component = "main", command = "setLevel", args = { 50 } },
    })
    
    test.wait_for_events()
    
    -- Verify PUT request was sent  
    put_conn:assert_sent("PUT /clip/v2/resource/light/11111111%-1111%-1111%-1111%-111111111111")
    
    -- Device should not emit state change on error
  end
)

test.register_coroutine_test(
  "Light command handles Hue API error in response body",
  function()
    http.expect_request_for_test(put_conn, "PUT", "/clip/v2/resource/light/" .. LIGHT_RID, {
      status = 200,
      body = {
        errors = {
          {
            description = "Light is unreachable"
          }
        },
        data = {}
      }
    })
    
    test.socket.capability:__queue_receive({
      mock_light.id,
      { capability = "switch", component = "main", command = "off", args = {} },
    })
    
    test.wait_for_events()
    put_conn:assert_sent("PUT /clip/v2/resource/light/11111111%-1111%-1111%-1111%-111111111111")
    
    -- Command should handle error gracefully (no crash, logs error)
  end
)

-- TODO: Re-enable timeout test with proper connection closing mechanism
-- The current ConnectionScenario framework doesn't have an easy way to simulate
-- an immediate connection close/timeout without actually waiting for the timeout to occur.
-- Need to either:
-- 1. Add a mechanism to immediately fail/close a connection after it's established
-- 2. Reduce the socket timeout for testing
-- 3. Use the old mock server's close_connection() approach
--[[
test.register_coroutine_test(
  "Light command handles connection timeout",
  function()
    -- Don't define expectation - let the connection timeout naturally
    -- by not having any response ready
    
    test.socket.capability:__queue_receive({
      mock_light.id,
      { capability = "switch", component = "main", command = "on", args = {} },
    })
    
    test.wait_for_events()
    
    -- Driver should handle timeout gracefully without crashing
    -- (timeout will occur because no expectation matched, so no response generated)
  end
)
--]]


test.register_coroutine_test(
  "Refresh handles missing zigbee connectivity gracefully",
  function()
    hue_test_helpers.mark_bridge_initialized(mock_bridge)
    
    -- Return device info without zigbee_connectivity service
    http.expect_request_for_test(get_conn, "GET", "/clip/v2/resource/device/" .. LIGHT_DEVICE_ID, {
      status = 200,
      body = {
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
      }
    })
    
    test.socket.capability:__queue_receive({
      mock_light.id,
      { capability = "refresh", component = "main", command = "refresh", args = {} },
    })
    
    test.wait_for_events()
    get_conn:assert_sent("GET /clip/v2/resource/device/22222222%-2222%-2222%-2222%-222222222222")
    
    -- Driver logs error about missing zigbee_connectivity and returns early
    -- (no light state fetch attempted, which is the correct behavior)
    -- Test passes if driver handles this gracefully without crashing
  end
)

test.register_coroutine_test(
  "Refresh handles 404 for deleted device",
  function()
    hue_test_helpers.mark_bridge_initialized(mock_bridge)
    
    -- Device info lookup returns 404 (device deleted on bridge)
    http.expect_request_for_test(get_conn, "GET", "/clip/v2/resource/device/" .. LIGHT_DEVICE_ID, {
      status = 404,
      body = {
        errors = {
          {
            type = "resource_not_found",
            description = "Device not found"
          }
        }
      }
    })
    
    test.socket.capability:__queue_receive({
      mock_light.id,
      { capability = "refresh", component = "main", command = "refresh", args = {} },
    })
    
    test.wait_for_events()
    get_conn:assert_sent("GET /clip/v2/resource/device/22222222%-2222%-2222%-2222%-222222222222")
    
    -- Should handle gracefully (logs error, doesn't crash)
  end
)

test.register_coroutine_test(
  "Malformed JSON response handled gracefully",
  function()
    -- Use connection:expect_for_test directly with raw response data
    put_conn:expect_for_test({
      request = { pattern = "^PUT /clip/v2/resource/light/11111111%-1111%-1111%-1111%-111111111111" },
      responses = {
        { data = http.format_response(200, {["content-type"] = "application/json"}, "{ invalid json") }
      }
    })
    
    test.socket.capability:__queue_receive({
      mock_light.id,
      { capability = "switch", component = "main", command = "on", args = {} },
    })
    
    test.wait_for_events()
    put_conn:assert_sent("PUT /clip/v2/resource/light/11111111%-1111%-1111%-1111%-111111111111")
    
    -- Driver should handle parse error without crashing
  end
)

test.register_coroutine_test(
  "Empty response body handled gracefully",
  function()
    -- Use connection:expect_for_test directly with empty body
    put_conn:expect_for_test({
      request = { pattern = "^PUT /clip/v2/resource/light/11111111%-1111%-1111%-1111%-111111111111" },
      responses = {
        { data = http.format_response(200, {["content-type"] = "application/json"}, "") }
      }
    })
    
    test.socket.capability:__queue_receive({
      mock_light.id,
      { capability = "switchLevel", component = "main", command = "setLevel", args = { 25 } },
    })
    
    test.wait_for_events()
    put_conn:assert_sent("PUT /clip/v2/resource/light/11111111%-1111%-1111%-1111%-111111111111")
    
    -- Driver should handle empty response without crashing
  end
)

test.run_registered_tests()
