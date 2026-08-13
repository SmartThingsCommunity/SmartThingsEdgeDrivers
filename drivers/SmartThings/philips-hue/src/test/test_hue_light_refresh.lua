local test = require "integration_test"
local capabilities = require "st.capabilities"
local hue_test_helpers = require "test.hue_test_helpers"

local LIGHT_RID = "22222222-2222-2222-2222-222222222222"
local HUE_DEVICE_ID = "device-uuid-1"
local ZIGBEE_RID = "zigbee-conn-1"

local mock_bridge, mock_light, get_bridge_server, test_init = hue_test_helpers.build_paired_bridge_and_light(
  LIGHT_RID,
  {
    on = { on = true },
    dimming = { brightness = 80 },
    hue_device_id = HUE_DEVICE_ID,
  },
  "white-and-color-ambiance.yml"
)

test.set_test_init_function(test_init)

--- The refresh capability command's non-cached path always refreshes zigbee connectivity
--- first (two REST calls: look up the device's zigbee_connectivity resource, then its status),
--- and light attribute events only ever emit once the device is marked online as a result.
local function queue_zigbee_online_responses()
  local server = get_bridge_server()
  server:queue_http_response(200, {}, {
    errors = {},
    data = { { services = { { rtype = "zigbee_connectivity", rid = ZIGBEE_RID } } } },
  })
  server:queue_http_response(200, {}, {
    errors = {},
    data = { { owner = { rid = HUE_DEVICE_ID }, status = "connected" } },
  })
end

test.register_coroutine_test(
  "refresh command reads light state over REST and emits switch/switchLevel events",
  function()
    hue_test_helpers.mark_bridge_initialized(mock_bridge)
    test.socket.capability:__queue_receive({
      mock_light.id,
      { capability = "refresh", component = "main", command = "refresh", args = {} },
    })
    queue_zigbee_online_responses()
    get_bridge_server():queue_http_response(200, {}, {
      errors = {},
      data = { { id = LIGHT_RID, on = { on = true }, dimming = { brightness = 80 } } },
    })
    test.socket.capability:__expect_send(
      mock_light:generate_test_message("main", capabilities.switch.switch.on())
    )
    test.socket.capability:__expect_send(
      mock_light:generate_test_message("main", capabilities.switchLevel.level(80))
    )
    test.wait_for_events()

    local server = get_bridge_server()
    server:expect_http_request("GET", "/clip/v2/resource/device/" .. HUE_DEVICE_ID)
    server:expect_http_request("GET", "/clip/v2/resource/zigbee_connectivity/" .. ZIGBEE_RID)
    server:expect_http_request("GET", "/clip/v2/resource/light/" .. LIGHT_RID)
  end
)

test.register_coroutine_test(
  "refresh command reflects an off/dimmed state from the REST response",
  function()
    hue_test_helpers.mark_bridge_initialized(mock_bridge)
    test.socket.capability:__queue_receive({
      mock_light.id,
      { capability = "refresh", component = "main", command = "refresh", args = {} },
    })
    queue_zigbee_online_responses()
    get_bridge_server():queue_http_response(200, {}, {
      errors = {},
      data = { { id = LIGHT_RID, on = { on = false }, dimming = { brightness = 15 } } },
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
