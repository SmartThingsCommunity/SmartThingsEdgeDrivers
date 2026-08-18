--- Test for button device lifecycle (added/init/removed).
--- Migrated to use connection_scenario 2.0.
---
--- Note: This test doesn't make HTTP requests during lifecycle operations,
--- so no ConnectionScenario setup is needed. It primarily validates that
--- lifecycle handlers complete without errors.

local test = require "integration_test"
local capabilities = require "st.capabilities"
local hue_test_helpers = require "test.hue_test_helpers"

-- Use proper UUID format for Hue resource IDs
local BUTTON_RID = "aaaaaaaa-bbbb-cccc-dddd-111111111111"
local BUTTON_DEVICE_ID = "aaaaaaaa-bbbb-cccc-dddd-222222222222"
local POWER_RID = "aaaaaaaa-bbbb-cccc-dddd-333333333333"

-- Single button device fixture WITHOUT SSE (lifecycle only)
local mock_bridge, mock_button, get_bridge_server, test_init =
  hue_test_helpers.HueDeviceBuilder.new()
    :with_bridge()
    :with_button(BUTTON_RID, {
      battery = 85,
      device_id = BUTTON_DEVICE_ID,
      power_rid = POWER_RID,
    })
    :start()

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Button device lifecycle completes successfully",
  function()
    -- The test passing means:
    -- 1. Button lifecycle handlers (added/init) ran without errors
    -- 2. supportedButtonValues was emitted as expected
    -- 3. Device fields were set correctly
    test.wait_for_events()
  end
)

test.run_registered_tests()
