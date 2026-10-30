-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- The bridge's SSE event stream: connecting marks the bridge online, update/add/delete events
--- reach the right devices, and a dropped stream marks everything offline until it reconnects.
---
--- The connectivity scan the driver makes once the stream connects is answered by a test-scoped
--- expectation registered after `activate()` in test_init, so a test can answer the scan after
--- a reconnect differently.

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
  :start()

local mock_bridge, mock_light = fixtures.bridge, fixtures.devices[1]

-- Create connection scenario with REST and SSE connections
local scenario, conns = hue_test_helpers.create_hue_scenario()
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

-- The light's refresh: its device, zigbee connectivity and light state. `opts` is passed to each
-- expectation (e.g. `times`).
local function expect_light_refresh(opts)
  local function expect(path, data)
    local spec = { body = { errors = {}, data = data } }
    for k, v in pairs(opts or {}) do spec[k] = v end
    http.expect_request(rest, "GET", path, spec)
  end
  expect("/clip/v2/resource/device/" .. HUE_DEVICE_ID,
    { { services = { { rtype = "zigbee_connectivity", rid = ZIGBEE_RID } } } })
  expect("/clip/v2/resource/zigbee_connectivity/" .. ZIGBEE_RID,
    { { owner = { rid = HUE_DEVICE_ID }, status = "connected" } })
  expect("/clip/v2/resource/light/" .. LIGHT_RID,
    { { id = LIGHT_RID, on = { on = true }, dimming = { brightness = 80 } } })
end

-- The refreshes injected by the light's added and init handlers.
expect_light_refresh({ times = 2 })
-- SSE handshake (reusable for reconnections)
http.expect_sse_handshake(sse, "/eventstream/clip/v2", true)

-- Custom test_init that pre-queues all init expectations before activating scenario
test.set_test_init_function(function()
  scenario:activate()

  -- The connectivity scan after the stream connects reports only a device outside the fixture.
  http.expect_request_for_test(rest, "GET", "/clip/v2/resource/zigbee_connectivity", {
    body = {
      errors = {},
      data = { { owner = { rid = "unrelated-device-not-in-fixture" }, status = "connected" } },
    },
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
  "an SSE dimming-only update for a light emits only its level",
  function()
    local sse_conn = connect_sse()

    -- The bridge only sends what changed: a brightness change carries no on/off state.
    http.queue_sse_event(sse_conn, {
      hue_test_helpers.light_event(LIGHT_RID, nil, 42)
    })
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
    http.expect_request_for_test(rest_conn, "GET", "/clip/v2/resource/light/" .. NEW_LIGHT_RID, {
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

    -- After reconnecting, the connectivity scan reports the light as connected, which refreshes it.
    http.expect_request_for_test(rest_conn, "GET", "/clip/v2/resource/zigbee_connectivity", {
      body = {
        errors = {},
        data = { { owner = { rid = HUE_DEVICE_ID }, status = "connected" } }
      },
    })
    expect_switch_and_level_emit()
    expect_light_refresh()

    test.wait_for_events()

    assert(mock_devices_api.__is_device_online(mock_bridge.id) == true,
      "expected the bridge to be marked online again after the SSE connection reconnected")
    assert(mock_devices_api.__is_device_online(mock_light.id) == true,
      "expected the light to be marked online when connectivity status reports it as connected")
  end
)

test.run_registered_tests()
