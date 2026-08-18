--- Test for child device lifecycle with uncached devices (stray device handling).
--- Migrated to use connection_scenario 2.0.
---
--- Tests that uncached child devices are properly marked as "stray" rather than
--- attempting to fetch their state via REST (which would fail/crash).
---
--- TODO: Expand test coverage to explicitly verify:
---   - Stray device field is set correctly on the uncached device
---   - No REST calls are made (could use ConnectionScenario with strict expectations)
---   - Appropriate log messages or warnings are emitted for stray devices
---   - Behavior when attempting to send commands to stray devices

local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local hue_test_helpers = require "test.hue_test_helpers"

-- A throwaway light used only to satisfy build_paired_bridge_and_light's fixture requirements
-- (it needs at least one light to seed the disco cache for). The device under test in this
-- file is mock_new_light below, which is deliberately *not* in the disco cache.
local THROWAWAY_LIGHT_RID = "33333333-3333-3333-3333-333333333333"
local NEW_LIGHT_RID = "44444444-4444-4444-4444-444444444444"

local mock_bridge, mock_throwaway_light, get_bridge_server, base_test_init =
  hue_test_helpers.HueDeviceBuilder.new()
    :with_bridge()
    :with_light(THROWAWAY_LIGHT_RID, {
      on = { on = true }
    }, "white-and-color-ambiance.yml")
    :start()

local mock_new_light = test.mock_device.build_test_lan_device({
  label = "New Hue Light",
  profile = t_utils.get_profile_definition("white-and-color-ambiance.yml"),
  parent_assigned_child_key = "light:" .. NEW_LIGHT_RID,
  parent_device_id = mock_bridge.id,
})

local function test_init()
  base_test_init()
  test.mock_device.add_test_device(mock_new_light)
  -- LightLifecycleHandlers.init unconditionally emits a levelRange event, regardless of
  -- whether the device's resource state is cached -- this has to be registered here (not in a
  -- test body) because the automatic device_lifecycle "init" delivery is fully processed 
  -- before a test's coroutine ever gets its first turn.
  hue_test_helpers.expect_light_init_events(mock_new_light)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "a child device added with no cached resource state is marked as a stray device rather than crashing",
  function()
    -- No REST call should be made for either light: the throwaway light's resource state is
    -- already cached (so light.lua's added handler skips the REST fetch it would otherwise
    -- need), and the new light never reaches light.lua's added handler at all --
    -- LifecycleHandlers.device_added checks disco's device_state_disco_cache *before* calling
    -- into it, so an uncached light is routed to StrayDeviceHelper instead. Both lights'
    -- levelRange emits (asserted via test_init, since that's where the expectations had to be
    -- registered) are the only thing expected to happen here.
    test.wait_for_events()
  end
)

test.run_registered_tests()
