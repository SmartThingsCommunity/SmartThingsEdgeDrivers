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
--- SSE is deliberately left uninitialized: `driver.joined_bridges`/`driver.datastore
--- .bridge_netinfo` are intentionally NOT populated for the bridge's own network-init step, so
--- `do_bridge_network_init` (which opens a persistent event-stream connection) never runs.
--- These fixtures are for REST-path tests only.
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
--- @return table mock_bridge
--- @return table mock_light
--- @return fun() get_bridge_server returns the current test run's
---   `integration_test.LanMockServer` for the bridge address; only valid to call from within a
---   test body (i.e. after `test_init` has run)
--- @return fun() test_init must be passed to `test.set_test_init_function`
function M.build_paired_bridge_and_light(light_rid, light_state, profile_filename, device_template_overrides)
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
    -- A swversion below PhilipsHueApi.MIN_CLIP_V2_SWVERSION routes both the bridge's
    -- "added"/"init" background retry loops into their terminal "ignored bridge" branch
    -- instead of retrying forever (which, since mock time advances instantly on every sleep,
    -- would spin the scheduler in a tight loop and hang the test) -- and, since
    -- driver.joined_bridges never becomes true, this also means do_bridge_network_init (which
    -- opens the persistent SSE event-stream connection) never runs. That's intentional: these
    -- fixtures are for REST-path tests only.
    driver.datastore.bridge_netinfo[M.BRIDGE_DNI] = { ip = M.BRIDGE_IP, swversion = "0", modelid = "BSB002" }
    driver.datastore.api_keys = driver.datastore.api_keys or {}
    driver.datastore.api_keys[M.BRIDGE_DNI] = M.API_KEY

    local disco = require "disco"
    -- disco is a module-level singleton that isn't necessarily reloaded between tests within
    -- the same file (integration_test.reset_tests() clears cosock's own thread bookkeeping, but
    -- has no idea this module-level cache exists). Without clearing it, a *stale* PhilipsHueApi
    -- instance from a previous test would get picked up here instead of a fresh one -- its
    -- background control thread was wiped by the reset, so requests made against it would
    -- silently never reach the (also freshly reset) mock socket at all.
    disco.disco_api_instances = {}
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

  local function test_init()
    test.mock_device.add_test_device(mock_bridge)
    test.mock_device.add_test_device(mock_light)

    mock_bridge:set_field(Fields.DEVICE_TYPE, "bridge", {})
    mock_bridge:set_field(Fields.BRIDGE_ID, M.BRIDGE_DNI, {})
    mock_bridge:set_field(Fields.IPV4, M.BRIDGE_IP, {})
    mock_bridge:set_field(HueApi.APPLICATION_KEY_HEADER, M.API_KEY, {})

    mock_bridge_server = lan_test_utils.build_mock_server(M.BRIDGE_IP, 443)

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

  return mock_bridge, mock_light, get_bridge_server, test_init
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

return M
