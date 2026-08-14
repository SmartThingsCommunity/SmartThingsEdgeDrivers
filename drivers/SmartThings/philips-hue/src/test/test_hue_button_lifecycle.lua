local test = require "integration_test"
local capabilities = require "st.capabilities"
local hue_test_helpers = require "test.hue_test_helpers"

-- Use proper UUID format for Hue resource IDs
local BUTTON_RID = "aaaaaaaa-bbbb-cccc-dddd-111111111111"
local BUTTON_DEVICE_ID = "aaaaaaaa-bbbb-cccc-dddd-222222222222"
local POWER_RID = "aaaaaaaa-bbbb-cccc-dddd-333333333333"

-- Single button device fixture WITHOUT SSE (lifecycle only)
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
      -- Register expectation for supportedButtonValues emit during init
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", 
          capabilities.button.supportedButtonValues(
            { "pushed", "held" },
            { visibility = { displayed = false } }
          )
        )
      )
    end,
    nil,  -- No device template overrides
    { enable_sse = false }  -- No SSE for lifecycle-only test
  )

test.set_test_init_function(base_test_init)

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
