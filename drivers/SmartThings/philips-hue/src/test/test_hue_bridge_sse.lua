--- Test for Hue bridge SSE connection lifecycle.
--- Migrated to use ConnectionScenario 2.0.
---
--- IMPORTANT PATTERN: Mixing Declarative Expectations Across Test Phases
---
--- ConnectionScenario's activate() resets expectation_index to 1 and removes non-persistent
--- expectations. This means you CANNOT define all expectations before activate() if different
--- tests need different responses to the same URL.
---
--- The solution: Add test-specific expectations AFTER activate() with persistent=false
--- 
--- Example from this file:
---   1. test_init adds shared expectations (refreshes, SSE handshake)
---   2. test_init calls activate() - this locks in persistent expectations and resets state
---   3. test_init adds the DEFAULT connectivity expectation AFTER activate() with persistent=false
---   4. Each test can add its OWN connectivity expectation that overrides the default
---
--- Why this works:
---   - activate() resets expectation_index to 1
---   - Driver consumes expectations 1-N during init
---   - expectation_index advances past the default expectations
---   - Test body adds NEW expectations at index N+1, N+2, etc.
---   - These new expectations are checked when driver makes reconnect requests
---   - persistent=false ensures they don't interfere with other tests
---
--- DO NOT try to use queue_bytes() (interactive pattern) for this - it doesn't work reliably
--- because you can't time when to queue the bytes relative to when the driver makes requests.

local test = require "integration_test"
local capabilities = require "st.capabilities"
local mock_devices_api = require "integration_test.mock_devices_api"
local hue_test_helpers = require "test.hue_test_helpers"
local http = require "integration_test.connection_scenario_http"

local LIGHT_RID = "22222222-2222-2222-2222-222222222222"
local HUE_DEVICE_ID = "device-uuid-1"
local ZIGBEE_RID = "zigbee-conn-1"

local NEW_DEVICE_RID = "66666666-6666-6666-6666-666666666666"
local NEW_LIGHT_RID = "77777777-7777-7777-7777-777777777777"
local NEW_LIGHT_NAME = "New Hue Light"

-- Create test fixture using HueDeviceBuilder
local fixtures = hue_test_helpers.HueDeviceBuilder.new()
  :with_bridge()
  :with_light(LIGHT_RID, {
    on = { on = true },
    dimming = { brightness = 80 },
    hue_device_id = HUE_DEVICE_ID,
  })
  :enable_sse()
  :start()

local mock_bridge, mock_light = fixtures.bridge, fixtures.devices[1]

-- Create connection scenario with REST and SSE connections
local scenario, conns = hue_test_helpers.create_hue_scenario({ sse = true })
local rest, sse = conns.rest, conns.sse

-- Helper to expect switch and level events
local function expect_switch_and_level_emit()
  test.socket.capability:__expect_send(
    mock_light:generate_test_message("main", capabilities.switch.switch.on())
  )
  test.socket.capability:__expect_send(
    mock_light:generate_test_message("main", capabilities.switchLevel.level(80))
  )
end

-- Helper to queue the initial light refresh responses (called twice during init)
local function queue_initial_light_refresh(rest_conn, light_on, light_brightness)
  light_on = light_on == nil and true or light_on
  light_brightness = light_brightness or 80
  
  http.expect_request(rest_conn, "GET", "/clip/v2/resource/device/" .. HUE_DEVICE_ID, {
    status = 200,
    body = {
      errors = {},
      data = { { services = { { rtype = "zigbee_connectivity", rid = ZIGBEE_RID } } } },
    }
  })
  
  http.expect_request(rest_conn, "GET", "/clip/v2/resource/zigbee_connectivity/" .. ZIGBEE_RID, {
    status = 200,
    body = {
      errors = {},
      data = { { owner = { rid = HUE_DEVICE_ID }, status = "connected" } },
    }
  })
  
  http.expect_request(rest_conn, "GET", "/clip/v2/resource/light/" .. LIGHT_RID, {
    status = 200,
    body = {
      errors = {},
      data = { { id = LIGHT_RID, on = { on = light_on }, dimming = { brightness = light_brightness } } },
    }
  })
end

-- Custom test_init that pre-queues all init expectations before activating scenario
test.set_test_init_function(function()
  -- Pre-queue all REST and SSE expectations for the init lifecycle
  queue_initial_light_refresh(rest, true, 80)  -- .added's injected refresh
  queue_initial_light_refresh(rest, true, 80)  -- .init's injected refresh
  
  -- SSE handshake (reusable for reconnections)
  http.expect_sse_handshake(sse, "/eventstream/clip/v2", true)
  
  -- NOTE: No connectivity poll expectation here!
  -- Each test must add its own connectivity expectation after activate()
  
  -- Now activate scenario BEFORE running init, so expectations are ready
  scenario:activate()
  
  -- After activate(), add the initial connectivity poll expectation
  -- This is non-persistent so it only applies to this test run
  http.expect_request(rest, "GET", "/clip/v2/resource/zigbee_connectivity", {
    status = 200,
    body = {
      errors = {},
      data = { { owner = { rid = "unrelated-device-not-in-fixture" }, status = "connected" } },
    },
    reusable = false,
    persistent = false
  })
  
  expect_switch_and_level_emit() -- from .added's injected refresh
  fixtures.test_init()            -- registers .init's levelRange emit
  expect_switch_and_level_emit() -- from .init's injected refresh
end)

--- Verifies that the SSE connection completed successfully during init.
local function connect_sse()
  test.wait_for_events()
  local sse_conn = scenario:get_connection("sse")
  local rest_conn = scenario:get_connection("rest")
  
  test.wait_for_events()

  assert(mock_devices_api.__is_device_online(mock_bridge.id) == true,
    "expected the bridge to be marked online after the SSE connection opened")
  assert(mock_devices_api.__is_device_online(mock_light.id) == true,
    "expected the light to be marked online from its own refresh's zigbee-connectivity check")

  return sse_conn, rest_conn
end

test.register_coroutine_test(
  "SSE connect marks the bridge online",
  function()
    connect_sse()
  end
)

test.register_coroutine_test(
  "an SSE update event for a light emits that light's attribute events",
  function()
    local sse_conn = connect_sse()

    http.queue_sse_event(sse_conn, {
      hue_test_helpers.light_event(LIGHT_RID, false, 42)
    })
    test.socket.capability:__expect_send(
      mock_light:generate_test_message("main", capabilities.switch.switch.off())
    )
    test.socket.capability:__expect_send(
      mock_light:generate_test_message("main", capabilities.switchLevel.level(42))
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "an SSE add event for a new device creates it",
  function()
    local sse_conn, rest_conn = connect_sse()

    mock_devices_api.__expect_create_device({
      type = "EDGE_CHILD",
      label = NEW_LIGHT_NAME,
      profileReference = "white",
      parentDeviceId = mock_bridge.id,
      manufacturer = "Signify Netherlands B.V.",
      model = "TEST",
      parentAssignedChildKey = "light:" .. NEW_LIGHT_RID,
    })

    http.queue_sse_event(sse_conn, {
      {
        type = "add",
        data = {
          {
            id = NEW_DEVICE_RID,
            id_v1 = "/lights/9",
            type = "device",
            metadata = { name = NEW_LIGHT_NAME },
            product_data = {
              manufacturer_name = "Signify Netherlands B.V.",
              model_id = "TEST",
              product_name = "Hue Light",
            },
            services = { { rtype = "light", rid = NEW_LIGHT_RID } },
          },
        },
      },
    })
    
    -- The driver queries the new light's state
    http.expect_request(rest_conn, "GET", "/clip/v2/resource/light/" .. NEW_LIGHT_RID, {
      status = 200,
      body = {
        errors = {},
        data = {
          {
            id = NEW_LIGHT_RID,
            type = "light",
            owner = { rid = NEW_DEVICE_RID },
            metadata = { name = NEW_LIGHT_NAME },
            on = { on = true },
            dimming = { brightness = 100 },
          },
        },
      }
    })
    
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "an SSE delete event for a device deletes it",
  function()
    local sse_conn = connect_sse()

    http.queue_sse_event(sse_conn, {
      { type = "delete", data = { { type = "light", id = LIGHT_RID } } },
    })
    test.wait_for_events()

    assert(mock_devices_api.__is_device_deleted(mock_light.id) == true,
      "expected the light to be deleted after an SSE delete event for its resource id")
  end
)

test.register_coroutine_test(
  "a dropped SSE connection marks everything offline, then reconnecting brings it back online",
  function()
    local sse_conn, rest_conn = connect_sse()

    sse_conn:close_connection()
    
    test.wait_for_events()

    assert(mock_devices_api.__is_device_online(mock_bridge.id) == false,
      "expected the bridge to be marked offline after the SSE connection errored")
    assert(mock_devices_api.__is_device_online(mock_light.id) == false,
      "expected the light to be marked offline after the SSE connection errored")

    -- Add test-specific expectations for the reconnect sequence
    -- These get appended to the expectations array. Since expectation_index is already
    -- past the init expectations, these new expectations will be matched when the
    -- driver makes reconnect requests.
    --
    -- KEY INSIGHT: The default connectivity expectation from test_init was marked
    -- persistent=false, so it was consumed during init and won't match again.
    -- This allows us to provide a DIFFERENT connectivity response for the reconnect.
    
    -- Connectivity poll response (returns the light as connected, unlike init)
    http.expect_request(rest_conn, "GET", "/clip/v2/resource/zigbee_connectivity", {
      status = 200,
      body = {
        errors = {},
        data = { { owner = { rid = HUE_DEVICE_ID }, status = "connected" } }
      },
      reusable = false
    })
    
    -- The "connected" status triggers a refresh, so expect the capability emissions
    expect_switch_and_level_emit()
    
    -- Queue expectations for the refresh sequence
    queue_initial_light_refresh(rest_conn, true, 80)

    test.wait_for_events()

    assert(mock_devices_api.__is_device_online(mock_bridge.id) == true,
      "expected the bridge to be marked online again after the SSE connection reconnected")
    assert(mock_devices_api.__is_device_online(mock_light.id) == true,
      "expected the light to be marked online when connectivity status reports it as connected")
  end
)

test.run_registered_tests()
