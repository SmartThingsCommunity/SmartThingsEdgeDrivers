-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- Test for Hue light command handling (switch, level, color, temperature).
--- Uses ConnectionScenario 2.0 for PUT command testing.

local test = require "integration_test"
local hue_test_helpers = require "test.hue_test_helpers"
local http = require "integration_test.connection_scenario_http"
local Fields = require "fields"

local LIGHT_RID = "11111111-1111-1111-1111-111111111111"

local fixtures = hue_test_helpers.HueDeviceBuilder.new()
  :with_bridge()
  :with_light(LIGHT_RID, {
    on = { on = true },
    dimming = { brightness = 100 },
    color = { xy = { x = 0.3, y = 0.3 }, gamut = { red = { x = 0.7, y = 0.3 }, green = { x = 0.2, y = 0.7 }, blue = { x = 0.15, y = 0.05 } } },
    color_temperature = { mirek = 366, mirek_schema = { mirek_minimum = 153, mirek_maximum = 500 } },
    mode = "normal",
  }, "white-and-color-ambiance.yml")
  :start()

local mock_light = fixtures.devices[1]

-- Set up ConnectionScenario for PUT command testing
local scenario, conns = hue_test_helpers.create_hue_scenario()
local rest = conns.rest

-- Setup test init with scenario activation
hue_test_helpers.setup_scenario_test_init(fixtures.test_init, scenario)

local LIGHT_PATH = "/clip/v2/resource/light/" .. LIGHT_RID

--- The xy the driver sent in its one PUT for the light.
local function sent_xy()
  local requests = http.find_requests(rest, "PUT", LIGHT_PATH)
  assert(#requests == 1, string.format("expected one PUT for the light, got %d", #requests))
  local xy = requests[1].json and requests[1].json.color and requests[1].json.color.xy
  assert(xy and type(xy.x) == "number" and type(xy.y) == "number", "expected color.xy in the request body")
  return xy
end

local function assert_xy_near(xy, x, y, what)
  local tolerance = 0.01
  assert(math.abs(xy.x - x) < tolerance and math.abs(xy.y - y) < tolerance,
    string.format("expected %s near (%.4f, %.4f), got (%.4f, %.4f)", what, x, y, xy.x, xy.y))
end


-- NOTE: Profile compatibility is implicitly tested here. The white-and-color-ambiance profile
-- supports all capabilities: switch, switchLevel, colorControl, and colorTemperature.
-- Tests for profile-restricted lights (white-only, white-ambiance) are in other test files
-- where those specific profiles make sense in context (e.g., test_hue_light_refresh.lua).

test.register_coroutine_test(
  "switch on command sends a PUT to turn the light on",
  function()
    -- Test-specific expectation: PUT command with OK response
    http.expect_request_for_test(rest, "PUT", "/clip/v2/resource/light/" .. LIGHT_RID, {
      status = 200,
      body = { data = { { rid = LIGHT_RID, rtype = "light" } } }
    })

    test.socket.capability:__queue_receive({
      mock_light.id,
      { capability = "switch", component = "main", command = "on", args = {} },
    })
    test.wait_for_events()

    -- Verify the request body contains the expected on=true
    http.assert_sent_json(rest, "PUT", LIGHT_PATH, { on = { on = true } })
  end
)

test.register_coroutine_test(
  "switch off command sends a PUT to turn the light off",
  function()
    http.expect_request_for_test(rest, "PUT", "/clip/v2/resource/light/" .. LIGHT_RID, {
      status = 200,
      body = { data = { { rid = LIGHT_RID, rtype = "light" } } }
    })

    test.socket.capability:__queue_receive({
      mock_light.id,
      { capability = "switch", component = "main", command = "off", args = {} },
    })
    test.wait_for_events()

    -- Verify the request body contains the expected on=false
    http.assert_sent_json(rest, "PUT", LIGHT_PATH, { on = { on = false } })
  end
)

test.register_coroutine_test(
  "setLevel command sends a PUT with the requested brightness",
  function()
    http.expect_request_for_test(rest, "PUT", "/clip/v2/resource/light/" .. LIGHT_RID, {
      status = 200,
      body = { data = { { rid = LIGHT_RID, rtype = "light" } } }
    })

    test.socket.capability:__queue_receive({
      mock_light.id,
      { capability = "switchLevel", component = "main", command = "setLevel", args = { 42 } },
    })
    test.wait_for_events()

    -- Verify the request body contains the expected brightness
    http.assert_sent_json(rest, "PUT", LIGHT_PATH, { dimming = { brightness = 42 } })
  end
)

test.register_coroutine_test(
  "setColorTemperature command sends a PUT with the mirek conversion of the requested Kelvin value",
  function()
    http.expect_request_for_test(rest, "PUT", "/clip/v2/resource/light/" .. LIGHT_RID, {
      status = 200,
      body = { data = { { rid = LIGHT_RID, rtype = "light" } } }
    })

    test.socket.capability:__queue_receive({
      mock_light.id,
      { capability = "colorTemperature", component = "main", command = "setColorTemperature", args = { 3000 } },
    })
    test.wait_for_events()

    -- Verify the request body contains the expected mirek value (3000K = 333 mirek)
    http.assert_sent_json(rest, "PUT", LIGHT_PATH, { color_temperature = { mirek = 333 }, on = { on = true } })
  end
)

test.register_coroutine_test(
  "setColor command converts HSV to XY and sends PUT with color",
  function()
    http.expect_request_for_test(rest, "PUT", "/clip/v2/resource/light/" .. LIGHT_RID, {
      status = 200,
      body = { data = { { rid = LIGHT_RID, rtype = "light" } } }
    })

    test.socket.capability:__queue_receive({
      mock_light.id,
      { capability = "colorControl", component = "main", command = "setColor", args = { { hue = 0, saturation = 100 } } },
    })
    test.wait_for_events()

    -- Hue 0 at full saturation is pure red: the red corner of the light's gamut.
    assert_xy_near(sent_xy(), 0.7, 0.3, "fully saturated red")
    http.assert_sent_json(rest, "PUT", LIGHT_PATH, { on = { on = true } })
  end
)

test.register_coroutine_test(
  "setHue combines the new hue with the light's current saturation",
  function()
    http.expect_request_for_test(rest, "PUT", "/clip/v2/resource/light/" .. LIGHT_RID, {
      status = 200,
      body = { data = { { rid = LIGHT_RID, rtype = "light" } } }
    })
    fixtures.driver_device(mock_light):set_field(Fields.COLOR_SATURATION, 100)

    test.socket.capability:__queue_receive({
      mock_light.id,
      { capability = "colorControl", component = "main", command = "setHue", args = { 0 } },
    })
    test.wait_for_events()

    -- Hue 0 at full saturation is pure red: the red corner of the light's gamut.
    assert_xy_near(sent_xy(), 0.7, 0.3, "fully saturated red")
  end
)

test.register_coroutine_test(
  "setSaturation combines the new saturation with the light's current hue",
  function()
    http.expect_request_for_test(rest, "PUT", "/clip/v2/resource/light/" .. LIGHT_RID, {
      status = 200,
      body = { data = { { rid = LIGHT_RID, rtype = "light" } } }
    })
    fixtures.driver_device(mock_light):set_field(Fields.COLOR_HUE, 33)

    test.socket.capability:__queue_receive({
      mock_light.id,
      { capability = "colorControl", component = "main", command = "setSaturation", args = { 0 } },
    })
    test.wait_for_events()

    -- No saturation is white whatever the hue: Hue's D65 white point.
    assert_xy_near(sent_xy(), 0.3227, 0.3290, "white")
  end
)

-- Out-of-range values sent from the SmartThings API during physical testing (scenario 15), and the
-- request bodies the driver sent the bridge for them.
local function expect_light_put()
  http.expect_request_for_test(rest, "PUT", "/clip/v2/resource/light/" .. LIGHT_RID, {
    status = 200,
    body = { data = { { rid = LIGHT_RID, rtype = "light" } } }
  })
end

test.register_coroutine_test(
  "setLevel 0 is clamped to the minimum brightness of 1",
  function()
    expect_light_put()
    test.socket.capability:__queue_receive({
      mock_light.id,
      { capability = "switchLevel", component = "main", command = "setLevel", args = { 0 } },
    })
    test.wait_for_events()

    http.assert_sent_json(rest, "PUT", "/clip/v2/resource/light/" .. LIGHT_RID, { dimming = { brightness = 1 } })
  end
)

for _, case in ipairs({
  { kelvin = 100, mirek = 500 },  -- below the light's range: its warmest setting
  { kelvin = 10000, mirek = 153 }, -- above the light's range: its coolest setting
}) do
  test.register_coroutine_test(
    string.format("setColorTemperature %dK is clamped to the light's range (mirek %d)", case.kelvin, case.mirek),
    function()
      expect_light_put()
      test.socket.capability:__queue_receive({
        mock_light.id,
        { capability = "colorTemperature", component = "main", command = "setColorTemperature", args = { case.kelvin } },
      })
      test.wait_for_events()

      http.assert_sent_json(rest, "PUT", "/clip/v2/resource/light/" .. LIGHT_RID,
        { color_temperature = { mirek = case.mirek }, on = { on = true } })
    end
  )
end

test.run_registered_tests()
