local test = require "integration_test"
local capabilities = require "st.capabilities"
local hue_test_helpers = require "test.hue_test_helpers"
local http = require "integration_test.connection_scenario_http"

local LIGHT_RID = "22222222-2222-2222-2222-222222222222"
local HUE_DEVICE_ID = "device-uuid-1"
local ZIGBEE_RID = "zigbee-conn-1"

local mock_bridge, mock_light, get_bridge_server, base_test_init =
  hue_test_helpers.HueDeviceBuilder.new()
    :with_bridge()
    :with_light(LIGHT_RID, {
      on = { on = true },
      dimming = { brightness = 80 },
      hue_device_id = HUE_DEVICE_ID,
    }, "white-and-color-ambiance.yml")
    :start()

-- Set up ConnectionScenario for REST-only testing
local scenario, conns = hue_test_helpers.create_hue_scenario()
local rest = conns.rest

-- Setup test init with scenario activation
hue_test_helpers.setup_scenario_test_init(base_test_init, scenario)

-- Define refresh sequence expectations
-- During refresh, the driver queries device info (to get zigbee_connectivity RID),
-- then checks zigbee connectivity, then queries light state

-- 1. GET device info to find zigbee_connectivity resource (reusable across tests)
hue_test_helpers.expect_device_info(rest, HUE_DEVICE_ID, 
  {{ rtype = "zigbee_connectivity", rid = ZIGBEE_RID }},
  { reusable = true }
)

-- 2. GET zigbee connectivity status (reusable across tests)
hue_test_helpers.expect_zigbee_connectivity(rest, ZIGBEE_RID, 
  { owner = HUE_DEVICE_ID, reusable = true }
)

-- Note: Light state expectations are test-specific and defined in each test body

test.register_coroutine_test(
  "refresh command reads light state over REST and emits switch/switchLevel events",
  function()
    hue_test_helpers.mark_bridge_initialized(mock_bridge)
    
    -- Test-specific expectation: light is on and bright
    http.expect_request_for_test(rest, "GET", "/clip/v2/resource/light/" .. LIGHT_RID, {
      status = 200,
      body = {
        errors = {},
        data = {{ id = LIGHT_RID, on = { on = true }, dimming = { brightness = 80 } }}
      }
    })
    
    test.socket.capability:__queue_receive({
      mock_light.id,
      { capability = "refresh", component = "main", command = "refresh", args = {} },
    })
    
    test.socket.capability:__expect_send(
      mock_light:generate_test_message("main", capabilities.switch.switch.on())
    )
    test.socket.capability:__expect_send(
      mock_light:generate_test_message("main", capabilities.switchLevel.level(80))
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "refresh command reflects an off/dimmed state from the REST response",
  function()
    hue_test_helpers.mark_bridge_initialized(mock_bridge)
    
    -- Test-specific expectation: light is off and dim
    http.expect_request_for_test(rest, "GET", "/clip/v2/resource/light/" .. LIGHT_RID, {
      status = 200,
      body = {
        errors = {},
        data = {{ id = LIGHT_RID, on = { on = false }, dimming = { brightness = 15 } }}
      }
    })
    
    test.socket.capability:__queue_receive({
      mock_light.id,
      { capability = "refresh", component = "main", command = "refresh", args = {} },
    })
    
    test.socket.capability:__expect_send(
      mock_light:generate_test_message("main", capabilities.switch.switch.off())
    )
    test.socket.capability:__expect_send(
      mock_light:generate_test_message("main", capabilities.switchLevel.level(15))
    )
    test.wait_for_events()
  end
)

test.run_registered_tests()
