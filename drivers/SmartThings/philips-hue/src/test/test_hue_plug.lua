-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- Tests for an on/off Hue smart plug (LOM010), built from payloads recorded on real hardware
--- (see test/fixtures/capture_payloads.lua). The plug is a `light` resource with no `dimming`.

local test = require "integration_test"
local capabilities = require "st.capabilities"
local hue_test_helpers = require "test.hue_test_helpers"
local http = require "integration_test.connection_scenario_http"
local capture_payloads = require "test.fixtures.capture_payloads"

local PLUG_RID = capture_payloads.ids.plug_light
local PLUG_DEVICE_ID = capture_payloads.ids.plug_device
local PLUG_ZIGBEE_RID = capture_payloads.ids.plug_zigbee

local function plug_light_resource(on)
  local resp = capture_payloads.get("plug_light")
  if on ~= nil then resp.data[1].on.on = on end
  return resp
end

local fixtures = hue_test_helpers.HueDeviceBuilder.new()
  :with_bridge()
  :with_light(PLUG_RID, {
    on = { on = true },
    hue_device_id = PLUG_DEVICE_ID,
    label = "Hue smart plug 1",
  }, "plug.yml")
  :start()

local mock_bridge, mock_plug = fixtures.bridge, fixtures.devices[1]

local scenario, conns = hue_test_helpers.create_hue_scenario()
local rest = conns.rest

hue_test_helpers.setup_scenario_test_init(fixtures.test_init, scenario)

http.expect_request(rest, "GET", "/clip/v2/resource/device/" .. PLUG_DEVICE_ID, {
  status = 200,
  body = capture_payloads.get("plug_device"),
})
hue_test_helpers.expect_zigbee_connectivity(rest, PLUG_ZIGBEE_RID, { owner = PLUG_DEVICE_ID, reusable = true })

local function refresh()
  test.socket.capability:__queue_receive({
    mock_plug.id,
    { capability = "refresh", component = "main", command = "refresh", args = {} },
  })
  test.socket.capability:__set_channel_ordering("relaxed")
  test.socket.capability:__expect_send(mock_plug:generate_test_message("main", capabilities["samsungim.hueSyncMode"].mode("normal")))
end

test.register_coroutine_test(
  "refreshing a plug emits its switch and sync mode state",
  function()
    hue_test_helpers.mark_bridge_initialized(mock_bridge)
    http.expect_request_for_test(rest, "GET", "/clip/v2/resource/light/" .. PLUG_RID, {
      status = 200,
      body = plug_light_resource(),
    })

    refresh()
    test.socket.capability:__expect_send(mock_plug:generate_test_message("main", capabilities.switch.switch.on()))
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "refreshing a plug that is off emits switch off",
  function()
    hue_test_helpers.mark_bridge_initialized(mock_bridge)
    http.expect_request_for_test(rest, "GET", "/clip/v2/resource/light/" .. PLUG_RID, {
      status = 200,
      body = plug_light_resource(false),
    })

    refresh()
    test.socket.capability:__expect_send(mock_plug:generate_test_message("main", capabilities.switch.switch.off()))
    test.wait_for_events()
  end
)

for _, command in ipairs({ "on", "off" }) do
  test.register_coroutine_test(
    "switch " .. command .. " sends a PUT to the plug's light resource",
    function()
      http.expect_request_for_test(rest, "PUT", "/clip/v2/resource/light/" .. PLUG_RID, {
        status = 200,
        body = { data = { { rid = PLUG_RID, rtype = "light" } }, errors = {} },
      })

      test.socket.capability:__queue_receive({
        mock_plug.id,
        { capability = "switch", component = "main", command = command, args = {} },
      })
      test.wait_for_events()

      http.assert_sent_json(rest, "PUT", "/clip/v2/resource/light/" .. PLUG_RID, { on = { on = command == "on" } })
    end
  )
end

test.run_registered_tests()
