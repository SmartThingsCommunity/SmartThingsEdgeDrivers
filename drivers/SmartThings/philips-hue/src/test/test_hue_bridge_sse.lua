local test = require "integration_test"
local capabilities = require "st.capabilities"
local mock_devices_api = require "integration_test.mock_devices_api"
local mock_lan_socket = require "integration_test.mock_lan_socket"
local hue_test_helpers = require "test.hue_test_helpers"

local LIGHT_RID = "22222222-2222-2222-2222-222222222222"
local HUE_DEVICE_ID = "device-uuid-1"
local ZIGBEE_RID = "zigbee-conn-1"

local NEW_DEVICE_RID = "66666666-6666-6666-6666-666666666666"
local NEW_LIGHT_RID = "77777777-7777-7777-7777-777777777777"
local NEW_LIGHT_NAME = "New Hue Light"

local mock_bridge, mock_light, get_bridge_server, test_init, get_sse_connection =
  hue_test_helpers.build_paired_bridge_and_light(
    LIGHT_RID,
    {
      on = { on = true },
      dimming = { brightness = 80 },
      hue_device_id = HUE_DEVICE_ID,
    },
    "white-and-color-ambiance.yml",
    nil,
    { enable_sse = true }
  )

local function expect_switch_and_level_emit()
  test.socket.capability:__expect_send(
    mock_light:generate_test_message("main", capabilities.switch.switch.on())
  )
  test.socket.capability:__expect_send(
    mock_light:generate_test_message("main", capabilities.switchLevel.level(80))
  )
end

-- Both LightLifecycleHandlers.added *and* .init unconditionally inject a "refresh" capability
-- command on every light add (light.lua:197 and light.lua:234, the latter gated on
-- Fields._REFRESH_AFTER_INIT, which .added unconditionally sets true) -- and unlike the
-- REST-only fixtures (where the bridge's own _INIT never becomes true, so those injected
-- refreshes just queue the device in driver._devices_pending_refresh and return), this fixture's
-- do_bridge_network_init runs for real and sets _INIT synchronously before the light's own
-- added/init lifecycle even starts. So *both* injected refreshes do a real, immediate REST round
-- trip here: one from .added (before .init's unconditional levelRange emit, which
-- hue_test_helpers.expect_light_init_events already expects), one from .init (right after that
-- levelRange emit) -- all three during the same automatic pre-test-body lifecycle burst lesson #1
-- describes. test.socket.capability:__expect_send enforces strict order against actual sends as
-- they occur, so all of this has to be registered here, in that exact chronological order,
-- around the wrapped test_init's own levelRange registration. (test_init itself runs fresh
-- before *every* registered test, not once per file, so every test needs this -- and its own
-- full SSE connect sequence below -- independently, same as any other Hue test file.)
test.set_test_init_function(function()
  expect_switch_and_level_emit() -- from .added's injected refresh
  test_init()                    -- registers .init's levelRange emit
  expect_switch_and_level_emit() -- from .init's injected refresh
end)

--- That injected refresh's own connect() and the SSE EventSource's own connect() both race for
--- this address right after test_init returns, and *which one* claims the single "sse"
--- reservation test_init made isn't reliably ordered (it can flip depending on unrelated timing,
--- e.g. table/coroutine hashing) -- so this doesn't assume an order; it peeks at whichever
--- connection actually claimed the "sse" label's first sent bytes (a non-consuming read, unlike
--- `expect_http_request`) to tell the two apart, then returns them correctly identified.
---
--- @return integration_test.LanMockServer sse the real SSE stream
--- @return integration_test.LanMockServer rest the bridge's persistent REST connection
local function identify_sse_and_rest_connections()
  test.wait_for_events()
  local sse_entry = mock_lan_socket.tcp_registry.get_labeled(hue_test_helpers.BRIDGE_IP, 443, "sse")
  local sent_so_far = table.concat(sse_entry.sent_log)
  if sent_so_far:match("^GET /eventstream/clip/v2 ") then
    return get_sse_connection(), get_bridge_server()
  end
  return get_bridge_server(), get_sse_connection()
end

--- Answers the REST calls `LightLifecycleHandlers.added`'s injected refresh makes (see above) --
--- the same zigbee-connectivity-then-light-state sequence test_hue_light_refresh.lua exercises
--- directly. All of the bridge's REST calls share one persistent connection (one PhilipsHueApi
--- instance, one worker thread processing requests serially), so this unconditional first
--- request has to be drained before anything else can get its response -- otherwise it blocks
--- every later REST call (including the SSE onopen's own connectivity poll) behind it.
---
--- @param rest integration_test.LanMockServer the bridge's REST connection (see
---   identify_sse_and_rest_connections)
local function answer_initial_light_refresh(rest)
  rest:queue_http_response(200, {}, {
    errors = {},
    data = { { services = { { rtype = "zigbee_connectivity", rid = ZIGBEE_RID } } } },
  })
  rest:queue_http_response(200, {}, {
    errors = {},
    data = { { owner = { rid = HUE_DEVICE_ID }, status = "connected" } },
  })
  rest:queue_http_response(200, {}, {
    errors = {},
    data = { { id = LIGHT_RID, on = { on = true }, dimming = { brightness = 80 } } },
  })
  test.wait_for_events()
  rest:expect_http_request("GET", "/clip/v2/resource/device/" .. HUE_DEVICE_ID)
  rest:expect_http_request("GET", "/clip/v2/resource/zigbee_connectivity/" .. ZIGBEE_RID)
  rest:expect_http_request("GET", "/clip/v2/resource/light/" .. LIGHT_RID)
end

--- Drives one full SSE connect: identifies which connection is which (see above), drains the
--- unconditional initial light refresh, then the EventSource handshake, then the
--- connectivity-status poll `onopen` makes before it settles (which also finishes flushing the
--- light's own `init` lifecycle -- its levelRange emit shares scheduler turns with all of this,
--- and finding the light "connected" here injects yet *another* refresh, independent of the
--- first). Every test calls this once, first thing -- `test_init` builds a fresh
--- bridge/light/EventSource per test (see above), so there's no persistent connection to share
--- across tests the way there might be within a single production run.
---
--- @return integration_test.LanMockServer sse
--- @return integration_test.LanMockServer rest
local function connect_sse()
  local sse, rest = identify_sse_and_rest_connections()
  answer_initial_light_refresh(rest) -- LightLifecycleHandlers.added's injected refresh
  answer_initial_light_refresh(rest) -- LightLifecycleHandlers.init's injected refresh

  sse:expect_http_request("GET", "/eventstream/clip/v2", {
    headers = { accept = "text/event-stream" },
  })
  sse:queue_sse_headers(200)
  -- The scheduler only advances one hop per wait_for_events(): this one lets the SSE
  -- coroutine read the handshake response and fire onopen, which itself spawns a *separate*
  -- background task to do the connectivity poll below -- that task needs its own turn too.
  test.wait_for_events()

  -- onopen's spawned task polls bridge-wide zigbee connectivity status before it settles; an
  -- empty (but successful) response would loop forever with no backoff, so this must have at
  -- least one entry -- deliberately for a resource id *not* one of this fixture's own child
  -- devices: a real match here (child_device_map[hue_device_id]) additionally injects yet
  -- *another* "refresh" capability command for that device (hue_bridge_utils.lua's onopen loop,
  -- independent of the one LightLifecycleHandlers.added already injects, and racing the same
  -- persistent REST connection), which every test would otherwise have to drain too. The light
  -- is already online from answer_initial_light_refresh's own zigbee-connectivity check above,
  -- same as it would be via a normal (non-SSE) refresh -- onopen's poll finding it "connected"
  -- isn't what this fixture relies on for that.
  rest:queue_http_response(200, {}, {
    errors = {},
    data = { { owner = { rid = "unrelated-device-not-in-fixture" }, status = "connected" } },
  })
  test.wait_for_events()
  -- Confirming the request landed (rather than just guessing a wait count) makes sure the poll
  -- loop's `scanned` flag has flipped and this REST round trip is fully done -- otherwise this
  -- task can still be mid-flight, holding the persistent REST connection, when a later test
  -- action tries to use it for something else.
  rest:expect_http_request("GET", "/clip/v2/resource/zigbee_connectivity")
  test.wait_for_events()

  assert(mock_devices_api.__is_device_online(mock_bridge.id) == true,
    "expected the bridge to be marked online after the SSE connection opened")
  assert(mock_devices_api.__is_device_online(mock_light.id) == true,
    "expected the light to be marked online from its own refresh's zigbee-connectivity check")

  return sse, rest
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
    local sse = connect_sse()

    sse:queue_sse_event({
      {
        type = "update",
        data = { { type = "light", id = LIGHT_RID, on = { on = false }, dimming = { brightness = 42 } } },
      },
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
    local sse, rest = connect_sse()

    mock_devices_api.__expect_create_device({
      type = "EDGE_CHILD",
      label = NEW_LIGHT_NAME,
      profileReference = "white",
      parentDeviceId = mock_bridge.id,
      manufacturer = "Signify Netherlands B.V.",
      model = "TEST",
      parentAssignedChildKey = "light:" .. NEW_LIGHT_RID,
    })

    sse:queue_sse_event({
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
    -- The "add" event is handled on a separate spawned task (hue_bridge_utils.lua's
    -- eventsource.onmessage), which itself makes a REST call to fetch the new light's state, over
    -- the same persistent REST connection.
    rest:queue_http_response(200, {}, {
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
    })
    test.wait_for_events()

    rest:expect_http_request("GET", "/clip/v2/resource/light/" .. NEW_LIGHT_RID)
  end
)

test.register_coroutine_test(
  "an SSE delete event for a device deletes it",
  function()
    local sse = connect_sse()

    sse:queue_sse_event({
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
    local sse, rest = connect_sse()

    sse:close_connection()
    test.wait_for_events()

    assert(mock_devices_api.__is_device_online(mock_bridge.id) == false,
      "expected the bridge to be marked offline after the SSE connection errored")
    assert(mock_devices_api.__is_device_online(mock_light.id) == false,
      "expected the light to be marked offline after the SSE connection errored")

    -- eventsource.lua's closed_action sleeps the default 1-second reconnect delay (genuinely
    -- mock-time-driven end to end now that cosock's timers fire correctly, and now that
    -- integration_test.set_test_coroutine_priority lets this test's own coroutine answer it
    -- before any *other* pending timeout can race ahead of it) before looping back to CONNECTING
    -- and reconnecting to the same address. Reserve the next "sse" connection and queue its
    -- handshake response *before* triggering that reconnect (rather than reacting afterward) --
    -- see mock_lan_socket.lua's get_labeled comment: this is exactly the "arm it ahead of time"
    -- case reserve/claim priority was built for.
    local reconnect_sse = get_bridge_server():reserve_connection("sse")
    reconnect_sse:queue_sse_headers(200)
    test.wait_for_events()

    reconnect_sse:expect_http_request("GET", "/eventstream/clip/v2", {
      headers = { accept = "text/event-stream" },
    })

    -- onopen's connectivity poll runs again on reconnect; answer with this fixture's own light
    -- reporting "connected" this time (unlike the first connect's answer_initial_light_refresh
    -- calls, which deliberately used an unrelated device id to avoid this), so both the bridge
    -- (marked online directly by onopen) and the light (marked online by this status) end up
    -- back online, matching what a real reconnect looks like.
    rest:queue_http_response(200, {}, {
      errors = {},
      data = { { owner = { rid = HUE_DEVICE_ID }, status = "connected" } },
    })
    test.wait_for_events()
    rest:expect_http_request("GET", "/clip/v2/resource/zigbee_connectivity")

    -- A "connected" status also injects another refresh capability command for the light --
    -- the same shape as the ones LightLifecycleHandlers.added/.init already trigger.
    expect_switch_and_level_emit()
    answer_initial_light_refresh(rest)

    assert(mock_devices_api.__is_device_online(mock_bridge.id) == true,
      "expected the bridge to be marked online again after the SSE connection reconnected")
    assert(mock_devices_api.__is_device_online(mock_light.id) == true,
      "expected the light to be marked online again after the reconnect's connectivity poll found it connected")
  end
)

test.run_registered_tests()
