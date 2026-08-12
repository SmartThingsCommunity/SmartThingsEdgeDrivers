--- Test for Hue light command handling (switch, level, color, temperature).
--- Migrated to use connection_scenario 2.0 with helper functions.

local test = require "integration_test"
local hue_test_helpers = require "test.hue_test_helpers"
local http = require "integration_test.connection_scenario_http"

local LIGHT_RID = "11111111-1111-1111-1111-111111111111"

local mock_bridge, mock_light, get_bridge_server, base_test_init = 
  hue_test_helpers.HueDeviceBuilder.new()
    :with_bridge()
    :with_light(LIGHT_RID, {
      on = { on = true },
      dimming = { brightness = 100 },
      color = { xy = { x = 0.3, y = 0.3 }, gamut = { red = { x = 0.7, y = 0.3 }, green = { x = 0.2, y = 0.7 }, blue = { x = 0.15, y = 0.05 } } },
      color_temperature = { mirek = 366, mirek_schema = { mirek_minimum = 153, mirek_maximum = 500 } },
      mode = "normal",
    }, "white-and-color-ambiance.yml")
    :start()

-- Set up ConnectionScenario for PUT command testing
local scenario, conns = hue_test_helpers.create_hue_scenario({ 
  rest = true,
  rest_method = "PUT"  -- Override default GET to PUT for commands
})
local rest = conns.rest

-- Setup test init with scenario activation
hue_test_helpers.setup_scenario_test_init(base_test_init, scenario)

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
    rest:assert_sent('"on":%s*{%s*"on":%s*true%s*}')
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
    rest:assert_sent('"on":%s*{%s*"on":%s*false%s*}')
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
    rest:assert_sent('"dimming":%s*{%s*"brightness":%s*42')
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
    rest:assert_sent('"color_temperature":%s*{%s*"mirek":%s*333')
    rest:assert_sent('"on":%s*{%s*"on":%s*true%s*}')
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

    -- Extract and parse the JSON body from the request
    local sent = rest:get_sent_log()
    local body_json = sent:match("\r\n\r\n(.+)")
    assert(body_json, "Expected to find request body")
    
    local dkjson = require("dkjson")
    local body = dkjson.decode(body_json)
    
    -- Verify the request body has the expected structure
    assert(body.color ~= nil, "Expected color in body")
    assert(body.color.xy ~= nil, "Expected color.xy in body")
    assert(type(body.color.xy.x) == "number", "Expected color.xy.x to be a number")
    assert(type(body.color.xy.y) == "number", "Expected color.xy.y to be a number")
    assert(body.on ~= nil and body.on.on == true, "Expected light to be turned on")
    
    -- Validate specific XY values for red (hue=0, saturation=100)
    -- Expected: x=0.7, y=0.3 (gamut red point)
    local tolerance = 0.01
    assert(math.abs(body.color.xy.x - 0.7) < tolerance, 
      string.format("Expected x≈0.7 but got %.6f", body.color.xy.x))
    assert(math.abs(body.color.xy.y - 0.3) < tolerance,
      string.format("Expected y≈0.3 but got %.6f", body.color.xy.y))
  end
)

test.register_coroutine_test(
  "setHue command uses existing saturation and sends PUT with color",
  function()
    http.expect_request_for_test(rest, "PUT", "/clip/v2/resource/light/" .. LIGHT_RID, {
      status = 200,
      body = { data = { { rid = LIGHT_RID, rtype = "light" } } }
    })
    
    -- Set initial saturation field
    mock_light:set_field("_color_saturation", 50)
    
    test.socket.capability:__queue_receive({
      mock_light.id,
      { capability = "colorControl", component = "main", command = "setHue", args = { 240 } }, -- Blue hue
    })
    test.wait_for_events()

    -- Extract and parse the JSON body from the request
    local sent = rest:get_sent_log()
    local body_json = sent:match("\r\n\r\n(.+)")
    assert(body_json, "Expected to find request body")
    
    local dkjson = require("dkjson")
    local body = dkjson.decode(body_json)
    
    -- Verify color.xy structure exists
    assert(body.color ~= nil, "Expected color in body")
    assert(body.color.xy ~= nil, "Expected color.xy in body")
    assert(type(body.color.xy.x) == "number", "Expected color.xy.x to be a number")
    assert(type(body.color.xy.y) == "number", "Expected color.xy.y to be a number")
    
    -- Validate specific XY values for blue hue=240 with saturation=50
    -- Expected: x≈0.323, y≈0.329
    local tolerance = 0.01
    assert(math.abs(body.color.xy.x - 0.323) < tolerance,
      string.format("Expected x≈0.323 but got %.6f", body.color.xy.x))
    assert(math.abs(body.color.xy.y - 0.329) < tolerance,
      string.format("Expected y≈0.329 but got %.6f", body.color.xy.y))
  end
)

test.register_coroutine_test(
  "setSaturation command uses existing hue and sends PUT with color",
  function()
    http.expect_request_for_test(rest, "PUT", "/clip/v2/resource/light/" .. LIGHT_RID, {
      status = 200,
      body = { data = { { rid = LIGHT_RID, rtype = "light" } } }
    })
    
    -- Set initial hue field
    mock_light:set_field("_color_hue", 120) -- Green hue
    
    test.socket.capability:__queue_receive({
      mock_light.id,
      { capability = "colorControl", component = "main", command = "setSaturation", args = { 75 } },
    })
    test.wait_for_events()

    -- Extract and parse the JSON body from the request
    local sent = rest:get_sent_log()
    local body_json = sent:match("\r\n\r\n(.+)")
    assert(body_json, "Expected to find request body")
    
    local dkjson = require("dkjson")
    local body = dkjson.decode(body_json)
    
    -- Verify color.xy structure exists
    assert(body.color ~= nil, "Expected color in body")
    assert(body.color.xy ~= nil, "Expected color.xy in body")
    assert(type(body.color.xy.x) == "number", "Expected color.xy.x to be a number")
    assert(type(body.color.xy.y) == "number", "Expected color.xy.y to be a number")
    
    -- Validate specific XY values for green hue=120 with saturation=75
    -- Expected: x≈0.645, y≈0.304
    local tolerance = 0.01
    assert(math.abs(body.color.xy.x - 0.645) < tolerance,
      string.format("Expected x≈0.645 but got %.6f", body.color.xy.x))
    assert(math.abs(body.color.xy.y - 0.304) < tolerance,
      string.format("Expected y≈0.304 but got %.6f", body.color.xy.y))
  end
)

test.run_registered_tests()
