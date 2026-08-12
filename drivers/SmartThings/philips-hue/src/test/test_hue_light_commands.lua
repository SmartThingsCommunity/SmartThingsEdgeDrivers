local test = require "integration_test"
local hue_test_helpers = require "test.hue_test_helpers"

local LIGHT_RID = "11111111-1111-1111-1111-111111111111"

local mock_bridge, mock_light, get_bridge_server, test_init = hue_test_helpers.build_paired_bridge_and_light(
  LIGHT_RID,
  {
    on = { on = true },
    dimming = { brightness = 100 },
    color = { xy = { x = 0.3, y = 0.3 }, gamut = { red = { x = 0.7, y = 0.3 }, green = { x = 0.2, y = 0.7 }, blue = { x = 0.15, y = 0.05 } } },
    color_temperature = { mirek = 366, mirek_schema = { mirek_minimum = 153, mirek_maximum = 500 } },
    mode = "normal",
  },
  "white-and-color-ambiance.yml"
)

test.set_test_init_function(test_init)

local function queue_ok_response()
  get_bridge_server():queue_http_response(200, {}, { data = { { rid = LIGHT_RID, rtype = "light" } } })
end

test.register_coroutine_test(
  "switch on command sends a PUT to turn the light on",
  function()
    test.socket.capability:__queue_receive({
      mock_light.id,
      { capability = "switch", component = "main", command = "on", args = {} },
    })
    queue_ok_response()
    test.wait_for_events()

    get_bridge_server():expect_http_request(
      "PUT",
      "/clip/v2/resource/light/" .. LIGHT_RID,
      {
        headers = { ["hue-application-key"] = hue_test_helpers.API_KEY },
        body = { on = { on = true } },
      }
    )
  end
)

test.register_coroutine_test(
  "switch off command sends a PUT to turn the light off",
  function()
    test.socket.capability:__queue_receive({
      mock_light.id,
      { capability = "switch", component = "main", command = "off", args = {} },
    })
    queue_ok_response()
    test.wait_for_events()

    get_bridge_server():expect_http_request(
      "PUT",
      "/clip/v2/resource/light/" .. LIGHT_RID,
      { body = { on = { on = false } } }
    )
  end
)

test.register_coroutine_test(
  "setLevel command sends a PUT with the requested brightness",
  function()
    test.socket.capability:__queue_receive({
      mock_light.id,
      { capability = "switchLevel", component = "main", command = "setLevel", args = { 42 } },
    })
    queue_ok_response()
    test.wait_for_events()

    get_bridge_server():expect_http_request(
      "PUT",
      "/clip/v2/resource/light/" .. LIGHT_RID,
      { body = { dimming = { brightness = 42 } } }
    )
  end
)

test.register_coroutine_test(
  "setColorTemperature command sends a PUT with the mirek conversion of the requested Kelvin value",
  function()
    test.socket.capability:__queue_receive({
      mock_light.id,
      { capability = "colorTemperature", component = "main", command = "setColorTemperature", args = { 3000 } },
    })
    queue_ok_response()
    test.wait_for_events()

    get_bridge_server():expect_http_request(
      "PUT",
      "/clip/v2/resource/light/" .. LIGHT_RID,
      { body = { color_temperature = { mirek = 333 }, on = { on = true } } }
    )
  end
)

test.run_registered_tests()
