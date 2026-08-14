local test = require "integration_test"
local t_utils = require "integration_test.utils"
local lan_test_utils = require "integration_test.lan_test_utils"
local capabilities = require "st.capabilities"

local Fields = require "fields"
local HueApi = require "hue.api"

--- Shared fixture helpers for building a "known, already paired" Hue bridge + child device(s)
--- for integration tests.
---
--- The real `added`/`init` lifecycle handlers do substantial discovery/pairing work (scanning
--- for the bridge on the network, waiting for the Link Button, querying the bridge for each
--- light's initial state, ...) that runs for real against the mock LAN socket every time a
--- test device goes through lifecycle. These helpers pre-populate every cache/datastore field
--- that work depends on (`driver.datastore.bridge_netinfo`/`.api_keys`, `disco`'s
--- `device_state_disco_cache`, per-device fields) so that added/init resolve synchronously to
--- a steady, already-paired state instead of falling into their discovery/long-poll paths --
--- those paths are covered separately in test_hue_bridge_discovery.lua.
---
--- SSE is deliberately left uninitialized by default: `driver.joined_bridges`/`driver.datastore
--- .bridge_netinfo` are populated with a swversion below `PhilipsHueApi.MIN_CLIP_V2_SWVERSION`,
--- so `do_bridge_network_init` (which opens a persistent event-stream connection) never runs.
--- Pass `opts = { enable_sse = true }` to `build_paired_bridge_and_light` to get the mirror image
--- instead -- a qualifying swversion and `driver.joined_bridges` pre-set, so `do_bridge_network_init`
--- runs for real (see `test_hue_bridge_sse.lua`).
local M = {}

M.BRIDGE_IP = "192.168.1.15"
M.BRIDGE_DNI = "AA:BB:CC:DD:EE:FF"
M.API_KEY = "test-api-key"

--- @param light_rid string the Hue resource ID for the light
--- @param light_state table the `HueLightInfo`-shaped state to seed `device_state_disco_cache`
---   with, e.g. `{ on = { on = true }, dimming = { brightness = 100 }, color = {...} }`
--- @param profile_filename string the light's profile YAML filename
--- @param device_template_overrides table|nil additional fields to merge into the light's
---   device template (e.g. `{ label = "..." }`)
--- @param opts table|nil `{ enable_sse = boolean }` -- see the module doc comment above
--- @return table mock_bridge
--- @return table mock_light
--- @return fun() get_bridge_server returns the current test run's
---   `integration_test.LanMockServer` for the bridge address; only valid to call from within a
---   test body (i.e. after `test_init` has run)
--- @return fun() test_init must be passed to `test.set_test_init_function`
--- @return fun() get_sse_connection only meaningful when `opts.enable_sse` is true; returns the
---   `integration_test.LanMockServer` handle bound to the bridge's SSE connection, valid once the
---   driver's `EventSource` has actually connected (see `test_hue_bridge_sse.lua`)
function M.build_paired_bridge_and_light(light_rid, light_state, profile_filename, device_template_overrides, opts)
  opts = opts or {}
  local mock_bridge = test.mock_device.build_test_lan_device({
    label = "Hue Bridge",
    profile = t_utils.get_profile_definition("hue-bridge.yml"),
    device_network_id = M.BRIDGE_DNI,
  })

  local light_template = {
    label = "Hue Light",
    profile = t_utils.get_profile_definition(profile_filename),
    -- Must match the "<device_type>:<rid>" format check_parent_assigned_child_key expects, or
    -- device_init's post-processing will issue an (unexpected, in these tests) metadata update.
    parent_assigned_child_key = "light:" .. light_rid,
    parent_device_id = mock_bridge.id,
  }
  for k, v in pairs(device_template_overrides or {}) do
    light_template[k] = v
  end
  local mock_light = test.mock_device.build_test_lan_device(light_template)

  local mock_bridge_server

  test.add_test_env_setup_func(function(driver)
    driver.datastore.bridge_netinfo = driver.datastore.bridge_netinfo or {}
    if opts.enable_sse then
      -- A qualifying swversion, plus driver.joined_bridges pre-set, routes
      -- BridgeLifecycleHandlers.init straight into its synchronous branch that calls
      -- do_bridge_network_init (which opens the persistent SSE event-stream connection) --
      -- see test_hue_bridge_sse.lua. Note the invariant this relies on: do_bridge_network_init
      -- also synchronously drains driver._devices_pending_refresh on the caller's thread before
      -- returning, and if that were non-empty it could open a REST connection to the same
      -- host:port *before* the SSE coroutine gets its first scheduler turn -- racing whatever
      -- connection reservation a test made for the SSE stream. It's empty by default; don't
      -- populate it in a test that also uses opts.enable_sse.
      driver.datastore.bridge_netinfo[M.BRIDGE_DNI] = { ip = M.BRIDGE_IP, swversion = tostring(HueApi.MIN_CLIP_V2_SWVERSION), modelid = "BSB002" }
      driver.joined_bridges[M.BRIDGE_DNI] = true
    else
      -- A swversion below PhilipsHueApi.MIN_CLIP_V2_SWVERSION routes both the bridge's
      -- "added"/"init" background retry loops into their terminal "ignored bridge" branch
      -- instead of retrying forever (which, since mock time advances instantly on every sleep,
      -- would spin the scheduler in a tight loop and hang the test) -- and, since
      -- driver.joined_bridges never becomes true, this also means do_bridge_network_init (which
      -- opens the persistent SSE event-stream connection) never runs. That's intentional: these
      -- fixtures are for REST-path tests only.
      driver.datastore.bridge_netinfo[M.BRIDGE_DNI] = { ip = M.BRIDGE_IP, swversion = "0", modelid = "BSB002" }
    end
    driver.datastore.api_keys = driver.datastore.api_keys or {}
    driver.datastore.api_keys[M.BRIDGE_DNI] = M.API_KEY

    local disco = require "disco"
    -- disco is a module-level singleton that isn't necessarily reloaded between tests within
    -- the same file (integration_test.reset_tests() clears cosock's own thread bookkeeping, but
    -- has no idea this module-level cache exists). Without clearing it, a *stale* PhilipsHueApi
    -- instance from a previous test would get picked up here instead of a fresh one -- its
    -- background control thread was wiped by the reset, so requests made against it would
    -- silently never reach the (also freshly reset) mock socket at all. discovery_active is the
    -- same class of singleton -- for the SSE fixture it's pre-set true so do_bridge_network_init's
    -- onopen skips its rediscovery scan (Discovery.scan_bridge_and_update_devices, which would
    -- otherwise make its own real mDNS/REST calls this fixture doesn't set up responses for);
    -- for the REST-only fixture it's just reset false for hygiene, since onopen never runs there.
    disco.disco_api_instances = {}
    disco.discovery_active = opts.enable_sse or false
    -- grouped_utils.scanning_enabled is the same class of singleton, reset here for the same
    -- hygiene reason. It defaults off for every fixture built by this helper: added unconditionally
    -- triggers a group scan for every light, whose own 45-second debounce would otherwise fire at
    -- some timing-dependent point during any test (now that cosock's timers actually work) and
    -- send real, unmocked rooms/zones REST requests that interleave with whatever the test itself
    -- is asserting on the same connection. A test that specifically wants to exercise group
    -- scanning should set it back to true itself, the same way mark_bridge_initialized overrides
    -- a different fixture default below.
    local grouped_utils = require "utils.grouped_utils"
    grouped_utils.scanning_enabled = false
    disco.device_state_disco_cache[light_rid] = {
      hue_provided_name = "Hue Light",
      id = light_rid,
      on = light_state.on or { on = true },
      color = light_state.color,
      dimming = light_state.dimming,
      color_temperature = light_state.color_temperature,
      mode = light_state.mode,
      parent_device_id = mock_bridge.id,
      hue_device_id = light_state.hue_device_id or (light_rid .. "-device"),
      hue_device_data = {
        product_data = {
          manufacturer_name = "Signify Netherlands B.V.",
          model_id = "TEST",
          product_name = "Hue Light",
        },
      },
    }
  end)

  local mock_sse_connection

  local function test_init()
    -- The driver template unconditionally spawns StrayDeviceHelper, a background thread with its
    -- own perpetually re-arming 30-second timeout. Now that cosock's timers actually fire (see
    -- cosock/timers.lua), that keeps the mock scheduler legitimately advancing mock time forever
    -- chasing it -- which, without this, can let some other, shorter-lived timeout a test needs
    -- to answer first (e.g. an injected refresh's 45-second REST reply-channel timeout) elapse
    -- for real before this test's own coroutine ever gets a turn to respond. See
    -- integration_test.set_test_coroutine_priority for the full rationale; scoped to Hue only
    -- since it changes *when* the test coroutine runs relative to background timers, which other
    -- drivers' test suites haven't been verified against.
    test.set_test_coroutine_priority(true)

    test.mock_device.add_test_device(mock_bridge)
    test.mock_device.add_test_device(mock_light)

    mock_bridge:set_field(Fields.DEVICE_TYPE, "bridge", {})
    mock_bridge:set_field(Fields.BRIDGE_ID, M.BRIDGE_DNI, {})
    mock_bridge:set_field(Fields.IPV4, M.BRIDGE_IP, {})
    mock_bridge:set_field(HueApi.APPLICATION_KEY_HEADER, M.API_KEY, {})

    mock_bridge_server = lan_test_utils.build_mock_server(M.BRIDGE_IP, 443)
    if opts.enable_sse then
      -- Reserved here, synchronously, before any lifecycle delivery happens. Two things race to
      -- connect to this address right after test_init returns: the SSE EventSource's own
      -- background coroutine (spawned inside do_bridge_network_init, which runs synchronously
      -- during the bridge's `init` handling) and LightLifecycleHandlers.added's
      -- unconditionally-injected "refresh" capability command (light.lua's join_light path).
      -- Whichever connects first claims this reservation -- which one that actually is isn't
      -- reliably ordered (it can flip on unrelated timing, e.g. table/coroutine hashing), so
      -- test_hue_bridge_sse.lua doesn't assume an order; it identifies which physical connection
      -- ended up being "sse" after the fact instead of trusting this reservation to always match
      -- the SSE stream. The other connection falls through to the address's default (shared)
      -- entry, same as every REST-only fixture -- and since all of the bridge's REST traffic
      -- shares one persistent connection (one PhilipsHueApi instance, one worker thread
      -- processing requests serially), that's the *only* other connection this fixture ever
      -- makes. See test_hue_bridge_sse.lua's answer_initial_light_refresh, which drains that
      -- connection's unconditional first request so it doesn't block later REST calls behind it.
      mock_sse_connection = mock_bridge_server:reserve_connection("sse")
    end

    -- Registering this expectation here -- rather than inside a test body -- matters, not just
    -- for style: Hue's driver template unconditionally spawns a StrayDeviceHelper background
    -- thread that loops on a 30-second-timeout channel receive forever. Since mock time
    -- advances instantly on any timeout, that thread always has an active timeout pending, so
    -- the mock scheduler's fallback that lets a test's own coroutine take its very first turn
    -- (which only fires when *no* thread has a pending timeout) never triggers -- a test body's
    -- coroutine would simply never run. The automatic startupState/device_lifecycle "init"
    -- delivery this framework already does happens *before* any of that (it's queued
    -- synchronously, ahead of `require "init"`), which is exactly why it still works -- so
    -- lifecycle-triggered expectations need to be registered the same way, from here, rather
    -- than from inside a coroutine test body.
    M.expect_light_init_events(mock_light)
  end

  local function get_bridge_server()
    assert(mock_bridge_server, "get_bridge_server() called before test_init() has run")
    return mock_bridge_server
  end

  local function get_sse_connection()
    assert(mock_sse_connection, "get_sse_connection() called without opts.enable_sse, or before test_init() has run")
    return mock_sse_connection
  end

  return mock_bridge, mock_light, get_bridge_server, test_init, get_sse_connection
end

--- `LightLifecycleHandlers.init` unconditionally emits a levelRange event on every light's
--- first init, regardless of bridge/pairing state. `build_paired_bridge_and_light`'s `test_init`
--- already calls this; only call it directly if building a fixture by hand.
---
--- Must be called from `test_init` (synchronous setup, before `require "init"` runs) rather
--- than from within a coroutine test body -- see the comment in `build_paired_bridge_and_light`
--- for why that distinction matters here.
---
--- @param mock_light table
function M.expect_light_init_events(mock_light)
  test.socket.capability:__expect_send(
    mock_light:generate_test_message("main", capabilities.switchLevel.levelRange({ minimum = 1, maximum = 100 }))
  )
end

--- Refresh (and other per-device flows) check that the bridge has finished initializing via
--- Fields._INIT, which is normally set inside do_bridge_network_init once bridge setup fully
--- completes -- the same step that creates the bridge's SSE EventSource. Since SSE connects to
--- the same host:port as REST calls, and the mock LAN socket models one connection per address,
--- letting do_bridge_network_init run for real would interleave the SSE connection's own bytes
--- into REST-focused assertions. Call this from within a test body (after the automatic
--- added/init lifecycle burst has already run -- i.e. as the first statement in the test, not
--- from test_init) to mark the bridge initialized directly instead.
---
--- @param mock_bridge table
function M.mark_bridge_initialized(mock_bridge)
  mock_bridge:set_field(Fields._INIT, true, {})
end

--- Build a paired bridge and generic child device (button, sensor, etc.)
--- Similar to build_paired_bridge_and_light but without light-specific assumptions
---
--- @param child_rid string the Hue resource ID for the child device
--- @param child_state table the device state to seed `device_state_disco_cache` with
--- @param profile_filename string the child device's profile YAML filename
--- @param device_type string the parent_assigned_child_key prefix (e.g., "button", "motion", "contact")
--- @param init_event_expectations fun(mock_child)|nil optional function to register init event expectations
--- @param device_template_overrides table|nil additional fields for the child device template
--- @param opts table|nil `{ enable_sse = boolean }` -- SSE is typically required for buttons/sensors
--- @return table mock_bridge
--- @return table mock_child
--- @return fun() get_bridge_server
--- @return fun() test_init
--- @return fun() get_sse_connection
function M.build_paired_bridge_and_child(child_rid, child_state, profile_filename, device_type, init_event_expectations, device_template_overrides, opts)
  opts = opts or {}
  local mock_bridge = test.mock_device.build_test_lan_device({
    label = "Hue Bridge",
    profile = t_utils.get_profile_definition("hue-bridge.yml"),
    device_network_id = M.BRIDGE_DNI,
  })

  local child_template = {
    label = child_state.hue_provided_name or ("Hue " .. device_type),
    profile = t_utils.get_profile_definition(profile_filename),
    parent_assigned_child_key = device_type .. ":" .. child_rid,
    parent_device_id = mock_bridge.id,
  }
  for k, v in pairs(device_template_overrides or {}) do
    child_template[k] = v
  end
  local mock_child = test.mock_device.build_test_lan_device(child_template)

  local mock_bridge_server

  test.add_test_env_setup_func(function(driver)
    driver.datastore.bridge_netinfo = driver.datastore.bridge_netinfo or {}
    if opts.enable_sse then
      driver.datastore.bridge_netinfo[M.BRIDGE_DNI] = { ip = M.BRIDGE_IP, swversion = tostring(HueApi.MIN_CLIP_V2_SWVERSION), modelid = "BSB002" }
      driver.joined_bridges[M.BRIDGE_DNI] = true
    else
      driver.datastore.bridge_netinfo[M.BRIDGE_DNI] = { ip = M.BRIDGE_IP, swversion = "0", modelid = "BSB002" }
    end
    driver.datastore.api_keys = driver.datastore.api_keys or {}
    driver.datastore.api_keys[M.BRIDGE_DNI] = M.API_KEY

    local disco = require "disco"
    disco.disco_api_instances = {}
    disco.discovery_active = opts.enable_sse or false
    local grouped_utils = require "utils.grouped_utils"
    grouped_utils.scanning_enabled = false
    
    -- Ensure parent_device_id is set correctly in child state
    child_state.parent_device_id = mock_bridge.id
    
    -- Populate disco cache with child device state
    disco.device_state_disco_cache[child_rid] = child_state
  end)

  local mock_sse_connection

  local function test_init()
    test.set_test_coroutine_priority(true)

    test.mock_device.add_test_device(mock_bridge)
    test.mock_device.add_test_device(mock_child)

    mock_bridge:set_field(Fields.DEVICE_TYPE, "bridge", {})
    mock_bridge:set_field(Fields.BRIDGE_ID, M.BRIDGE_DNI, {})
    mock_bridge:set_field(Fields.IPV4, M.BRIDGE_IP, {})
    mock_bridge:set_field(HueApi.APPLICATION_KEY_HEADER, M.API_KEY, {})
    -- Mark bridge as already added to prevent lifecycle handlers from treating child as stray
    mock_bridge:set_field(Fields._ADDED, true, { persist = true })
    -- Don't mark _INIT yet if SSE is enabled - let do_bridge_network_init run to set up SSE
    if not opts.enable_sse then
      mock_bridge:set_field(Fields._INIT, true, { persist = true })
    end

    mock_bridge_server = lan_test_utils.build_mock_server(M.BRIDGE_IP, 443)
    if opts.enable_sse then
      mock_sse_connection = mock_bridge_server:reserve_connection("sse")
    end

    -- Allow caller to register device-specific init expectations
    if init_event_expectations then
      init_event_expectations(mock_child)
    end
  end

  local function get_bridge_server()
    assert(mock_bridge_server, "get_bridge_server() called before test_init() has run")
    return mock_bridge_server
  end

  local function get_sse_connection()
    assert(mock_sse_connection, "get_sse_connection() called without opts.enable_sse, or before test_init() has run")
    return mock_sse_connection
  end

  return mock_bridge, mock_child, get_bridge_server, test_init, get_sse_connection
end

return M
