--- Tests for batched capability command handling: commands received together are sent to the
--- bridge as a single grouped_light request when they exactly cover a Hue room, and as
--- per-light requests otherwise.

-- Opt in to batched receives before requiring the framework: the driver checks for
-- `receive_batch` when it is loaded, and installs its batch handler only if it exists.
-- luacheck: globals _capability_batch_receive
_capability_batch_receive = true

local test = require "integration_test"
local hue_test_helpers = require "test.hue_test_helpers"
local http = require "integration_test.connection_scenario_http"
local Fields = require "fields"

local LIGHT_1_RID = "11111111-1111-1111-1111-111111111111"
local LIGHT_2_RID = "22222222-2222-2222-2222-222222222222"
local LIGHT_3_RID = "33333333-3333-3333-3333-333333333333"
local ROOM_RID = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
local GROUPED_LIGHT_RID = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"

local function light_state()
  return {
    on = { on = true },
    dimming = { brightness = 100 },
    color = { xy = { x = 0.3, y = 0.3 }, gamut = { red = { x = 0.7, y = 0.3 }, green = { x = 0.2, y = 0.7 }, blue = { x = 0.15, y = 0.05 } } },
    color_temperature = { mirek = 366, mirek_schema = { mirek_minimum = 153, mirek_maximum = 500 } },
    mode = "normal",
  }
end

-- Lights 1 and 2 make up the room; light 3 is outside it.
local fixtures = hue_test_helpers.HueDeviceBuilder.new()
  :with_bridge()
  :with_light(LIGHT_1_RID, light_state(), "white-and-color-ambiance.yml")
  :with_light(LIGHT_2_RID, light_state(), "white-and-color-ambiance.yml")
  :with_light(LIGHT_3_RID, light_state(), "white-and-color-ambiance.yml")
  :with_room(ROOM_RID, GROUPED_LIGHT_RID, { LIGHT_1_RID, LIGHT_2_RID }, "Living Room")
  :start()

local light_1, light_2, light_3 = fixtures.devices[1], fixtures.devices[2], fixtures.devices[3]

local scenario, conns = hue_test_helpers.create_hue_scenario({ rest = true, rest_method = "PUT" })
local rest = conns.rest

hue_test_helpers.setup_scenario_test_init(fixtures.test_init, scenario)

local function switch_cmd(command)
  return { capability = "switch", component = "main", command = command, args = {} }
end

local function step_level_cmd(step_size)
  return { capability = "statelessSwitchLevelStep", component = "main", command = "stepLevel", args = { step_size } }
end

local LIGHT_PATH = "/clip/v2/resource/light/"
local GROUPED_LIGHT_PATH = "/clip/v2/resource/grouped_light/"

local function expect_light_put(rid)
  http.expect_request_for_test(rest, "PUT", LIGHT_PATH .. rid, {
    status = 200,
    body = { data = { { rid = rid, rtype = "light" } } },
  })
end

local function expect_grouped_light_put(rid)
  http.expect_request_for_test(rest, "PUT", GROUPED_LIGHT_PATH .. rid, {
    status = 200,
    body = { data = { { rid = rid, rtype = "grouped_light" } } },
  })
end

--- Count requests sent in this test whose request line targets `path` (plain-text match).
local function count_requests(method, path)
  local sent = rest:get_sent_log()
  local needle = method .. " " .. path
  local count, start = 0, 1
  while true do
    local i = sent:find(needle, start, true)
    if not i then return count end
    count = count + 1
    start = i + #needle
  end
end

local function assert_requests(method, path, expected)
  local actual = count_requests(method, path)
  assert(actual == expected,
    string.format("expected %d %s %s request(s), got %d", expected, method, path, actual))
end

-- Let the lights finish initializing, then give the bridge its rooms.
local function init_and_seed_groups()
  test.wait_for_events()
  local groups = fixtures.seed_groups()
  assert(#groups == 1 and #groups[1].devices == 2,
    "expected 1 room with 2 light records, got " .. #groups .. " rooms")
end

test.register_coroutine_test(
  "a batch of one command is sent as a single light request",
  function()
    init_and_seed_groups()
    expect_light_put(LIGHT_1_RID)

    test.socket.capability:__queue_receive_batch({ { light_1.id, switch_cmd("on") } })
    test.wait_for_events()

    assert_requests("PUT", LIGHT_PATH .. LIGHT_1_RID, 1)
    assert_requests("PUT", GROUPED_LIGHT_PATH, 0)
    rest:assert_sent('"on":%s*{%s*"on":%s*true%s*}')
  end
)

test.register_coroutine_test(
  "a batch covering every light in a room is sent as one grouped_light request",
  function()
    init_and_seed_groups()
    expect_grouped_light_put(GROUPED_LIGHT_RID)

    test.socket.capability:__queue_receive_batch({
      { light_1.id, switch_cmd("on") },
      { light_2.id, switch_cmd("on") },
    })
    test.wait_for_events()

    assert_requests("PUT", GROUPED_LIGHT_PATH .. GROUPED_LIGHT_RID, 1)
    assert_requests("PUT", LIGHT_PATH, 0)
    rest:assert_sent('"on":%s*{%s*"on":%s*true%s*}')
  end
)

test.register_coroutine_test(
  "lights outside the matched room are still sent individually",
  function()
    init_and_seed_groups()
    expect_grouped_light_put(GROUPED_LIGHT_RID)
    expect_light_put(LIGHT_3_RID)

    test.socket.capability:__queue_receive_batch({
      { light_1.id, switch_cmd("off") },
      { light_2.id, switch_cmd("off") },
      { light_3.id, switch_cmd("off") },
    })
    test.wait_for_events()

    assert_requests("PUT", GROUPED_LIGHT_PATH .. GROUPED_LIGHT_RID, 1)
    assert_requests("PUT", LIGHT_PATH .. LIGHT_3_RID, 1)
    assert_requests("PUT", LIGHT_PATH, 1)
  end
)

test.register_coroutine_test(
  "matching commands that don't cover a whole room are sent individually",
  function()
    init_and_seed_groups()
    expect_light_put(LIGHT_1_RID)
    expect_light_put(LIGHT_3_RID)

    test.socket.capability:__queue_receive_batch({
      { light_1.id, switch_cmd("on") },
      { light_3.id, switch_cmd("on") },
    })
    test.wait_for_events()

    assert_requests("PUT", LIGHT_PATH .. LIGHT_1_RID, 1)
    assert_requests("PUT", LIGHT_PATH .. LIGHT_3_RID, 1)
    assert_requests("PUT", GROUPED_LIGHT_PATH, 0)
  end
)

test.register_coroutine_test(
  "commands with different arguments are not grouped",
  function()
    init_and_seed_groups()
    expect_light_put(LIGHT_1_RID)
    expect_light_put(LIGHT_2_RID)

    test.socket.capability:__queue_receive_batch({
      { light_1.id, switch_cmd("on") },
      { light_2.id, switch_cmd("off") },
    })
    test.wait_for_events()

    assert_requests("PUT", LIGHT_PATH .. LIGHT_1_RID, 1)
    assert_requests("PUT", LIGHT_PATH .. LIGHT_2_RID, 1)
    assert_requests("PUT", GROUPED_LIGHT_PATH, 0)
    rest:assert_sent('"on":%s*{%s*"on":%s*true%s*}')
    rest:assert_sent('"on":%s*{%s*"on":%s*false%s*}')
  end
)

test.register_coroutine_test(
  "commands without a grouped handler are sent individually even for a whole room",
  function()
    init_and_seed_groups()
    expect_light_put(LIGHT_1_RID)
    expect_light_put(LIGHT_2_RID)

    test.socket.capability:__queue_receive_batch({
      { light_1.id, step_level_cmd(10) },
      { light_2.id, step_level_cmd(10) },
    })
    test.wait_for_events()

    assert_requests("PUT", LIGHT_PATH .. LIGHT_1_RID, 1)
    assert_requests("PUT", LIGHT_PATH .. LIGHT_2_RID, 1)
    assert_requests("PUT", GROUPED_LIGHT_PATH, 0)
    rest:assert_sent('"dimming_delta"')
  end
)

local function set_level_cmd(level)
  return { capability = "switchLevel", component = "main", command = "setLevel", args = { level } }
end

local function set_switch_state(mock_light, state)
  fixtures.driver_device(mock_light):set_field(Fields.SWITCH_STATE, state, { persist = true })
end

test.register_coroutine_test(
  "a grouped setLevel for a room that is already on only sends the brightness",
  function()
    init_and_seed_groups()
    set_switch_state(light_1, "on")
    set_switch_state(light_2, "on")
    expect_grouped_light_put(GROUPED_LIGHT_RID)

    test.socket.capability:__queue_receive_batch({
      { light_1.id, set_level_cmd(23) },
      { light_2.id, set_level_cmd(23) },
    })
    test.wait_for_events()

    assert_requests("PUT", GROUPED_LIGHT_PATH .. GROUPED_LIGHT_RID, 1)
    rest:assert_sent('"dimming":%s*{%s*"brightness":%s*23%s*}')
    assert(not rest:get_sent_log():find('"on":', 1, true), "expected no on/off request for a room that is already on")
  end
)

test.register_coroutine_test(
  "a grouped setLevel turns the room on first when one of its lights is off",
  function()
    init_and_seed_groups()
    set_switch_state(light_1, "on")
    set_switch_state(light_2, "off")
    expect_grouped_light_put(GROUPED_LIGHT_RID)
    expect_grouped_light_put(GROUPED_LIGHT_RID)

    test.socket.capability:__queue_receive_batch({
      { light_1.id, set_level_cmd(23) },
      { light_2.id, set_level_cmd(23) },
    })
    test.wait_for_events()

    assert_requests("PUT", GROUPED_LIGHT_PATH .. GROUPED_LIGHT_RID, 2)
    rest:assert_sent('"on":%s*{%s*"on":%s*true%s*}')
    rest:assert_sent('"dimming":%s*{%s*"brightness":%s*23%s*}')
  end
)

test.run_registered_tests()
