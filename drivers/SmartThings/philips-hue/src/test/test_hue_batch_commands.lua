-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- Tests for batched capability command handling: commands received together are sent to the
--- bridge as a single grouped_light request when they exactly cover a Hue room or zone, and as
--- per-light requests otherwise. The rooms and zones come from the driver's own scan of the
--- bridge, which it runs (debounced) once the lights are added and the event stream connects.

-- Batched receives are turned on for every Hue test file by test.hue_test_helpers.
local test = require "integration_test"
local hue_test_helpers = require "test.hue_test_helpers"
local http = require "integration_test.connection_scenario_http"
local capabilities = require "st.capabilities"
local Fields = require "fields"

local LIGHT_1_RID = "11111111-1111-1111-1111-111111111111"
local LIGHT_2_RID = "22222222-2222-2222-2222-222222222222"
local LIGHT_3_RID = "33333333-3333-3333-3333-333333333333"
local LIGHT_4_RID = "44444444-4444-4444-4444-444444444444"
local LIGHT_5_RID = "55555555-5555-5555-5555-555555555555"
local ROOM_RID = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
local GROUPED_LIGHT_RID = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
local ZONE_RID = "cccccccc-cccc-cccc-cccc-cccccccccccc"
local ZONE_GROUPED_LIGHT_RID = "dddddddd-dddd-dddd-dddd-dddddddddddd"
local OTHER_ROOM_RID = "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"
local OTHER_ROOM_GROUPED_LIGHT_RID = "ffffffff-ffff-ffff-ffff-ffffffffffff"
-- A Hue device on the bridge (e.g. one added after onboarding) that the driver has no record of.
local UNKNOWN_DEVICE_ID = "99999999-9999-9999-9999-999999999999"

local function light_state()
  return { on = { on = true }, dimming = { brightness = 100 }, mode = "normal" }
end

-- Lights 1 and 2 make up the room and lights 4 and 5 the zone. Light 3 shares a second room with a
-- device the driver doesn't know about, so that room can't be used to control it.
local fixtures = hue_test_helpers.HueDeviceBuilder.new()
  :with_bridge()
  :with_light(LIGHT_1_RID, light_state(), "white-and-color-ambiance.yml")
  :with_light(LIGHT_2_RID, light_state(), "white-and-color-ambiance.yml")
  :with_light(LIGHT_3_RID, light_state(), "white-and-color-ambiance.yml")
  :with_light(LIGHT_4_RID, light_state(), "white-and-color-ambiance.yml")
  :with_light(LIGHT_5_RID, light_state(), "white-and-color-ambiance.yml")
  :with_room(ROOM_RID, GROUPED_LIGHT_RID, { LIGHT_1_RID, LIGHT_2_RID }, "Living Room")
  :with_zone(ZONE_RID, ZONE_GROUPED_LIGHT_RID, { LIGHT_4_RID, LIGHT_5_RID }, "Reading Corner")
  :expect_light_init_refreshes()
  :start()

local mock_bridge = fixtures.bridge
local light_1, light_2, light_3 = fixtures.devices[1], fixtures.devices[2], fixtures.devices[3]
local light_4, light_5 = fixtures.devices[4], fixtures.devices[5]

local rooms = fixtures.rooms
table.insert(rooms, hue_test_helpers.room_resource(OTHER_ROOM_RID, OTHER_ROOM_GROUPED_LIGHT_RID,
  { fixtures.configs.light[3].device_id, UNKNOWN_DEVICE_ID }, "Hallway"))

local scenario, conns = hue_test_helpers.create_hue_scenario({ rooms = rooms, zones = fixtures.zones })
local rest, sse = conns.rest, conns.sse

for _, light_config in ipairs(fixtures.configs.light) do
  hue_test_helpers.setup_light_init_expectations(rest, light_config)
end
hue_test_helpers.setup_sse_expectations(sse, rest)

hue_test_helpers.setup_scenario_test_init(function()
  fixtures.test_init()
  -- The lights initialize concurrently, each waiting on its own refresh's requests, so their init
  -- events interleave; each light's own events are still in order.
  test.socket.capability:__set_channel_ordering("relaxed")
end, scenario)

local function switch_cmd(command)
  return { capability = "switch", component = "main", command = command, args = {} }
end

local function step_level_cmd(step_size)
  return { capability = "statelessSwitchLevelStep", component = "main", command = "stepLevel", args = { step_size } }
end

local LIGHT_PATH = "/clip/v2/resource/light/"
local GROUPED_LIGHT_PATH = "/clip/v2/resource/grouped_light/"

--- Expect a PUT for a light, optionally requiring its JSON body to contain `json`.
local function expect_light_put(rid, json)
  http.expect_request_for_test(rest, "PUT", LIGHT_PATH .. rid, {
    request_json = json,
    status = 200,
    body = { data = { { rid = rid, rtype = "light" } } },
  })
end

--- Expect a PUT for a grouped_light, optionally requiring its JSON body to contain `json`.
local function expect_grouped_light_put(rid, json)
  http.expect_request_for_test(rest, "PUT", GROUPED_LIGHT_PATH .. rid, {
    request_json = json,
    status = 200,
    body = { data = { { rid = rid, rtype = "grouped_light" } } },
  })
end

local function assert_requests(method, path, expected)
  -- `path` is either a full resource path or a collection prefix like LIGHT_PATH.
  local actual = http.count_requests(rest, method, path, { prefix = true })
  assert(actual == expected,
    string.format("expected %d %s %s request(s), got %d", expected, method, path, actual))
end

-- Let the lights finish initializing, then let mock time pass until the driver's (debounced)
-- room and zone scan has run and found the bridge's groups.
local function init_and_scan_groups()
  hue_test_helpers.wait_for_init(scenario, mock_bridge)
  local bridge = fixtures.driver_device(mock_bridge)
  test.wait_until(function()
    return http.count_requests(rest, "GET", "/clip/v2/resource/zone") >= 1 and bridge:get_field(Fields.GROUPS) ~= nil
  end, { max_turns = 500, message = "the room and zone scan" })
  assert(http.count_requests(rest, "GET", "/clip/v2/resource/room") >= 1, "expected the room scan")
  -- Back to strict ordering for the events of the test itself.
  test.socket.capability:__set_channel_ordering("strict")
end

test.register_coroutine_test(
  "a batch of one command is sent as a single light request",
  function()
    init_and_scan_groups()
    expect_light_put(LIGHT_1_RID)

    test.socket.capability:__queue_receive_batch({ { light_1.id, switch_cmd("on") } })
    test.wait_for_events()

    assert_requests("PUT", LIGHT_PATH .. LIGHT_1_RID, 1)
    assert_requests("PUT", GROUPED_LIGHT_PATH, 0)
    http.assert_sent_json(rest, "PUT", LIGHT_PATH .. LIGHT_1_RID, { on = { on = true } })
  end
)

test.register_coroutine_test(
  "a batch covering every light in a room is sent as one grouped_light request",
  function()
    init_and_scan_groups()
    expect_grouped_light_put(GROUPED_LIGHT_RID)

    test.socket.capability:__queue_receive_batch({
      { light_1.id, switch_cmd("on") },
      { light_2.id, switch_cmd("on") },
    })
    test.wait_for_events()

    assert_requests("PUT", GROUPED_LIGHT_PATH .. GROUPED_LIGHT_RID, 1)
    assert_requests("PUT", LIGHT_PATH, 0)
    http.assert_sent_json(rest, "PUT", GROUPED_LIGHT_PATH .. GROUPED_LIGHT_RID, { on = { on = true } })
  end
)

test.register_coroutine_test(
  "lights outside the matched room are still sent individually",
  function()
    init_and_scan_groups()
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
    init_and_scan_groups()
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
    init_and_scan_groups()
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
    http.assert_sent_json(rest, "PUT", LIGHT_PATH .. LIGHT_1_RID, { on = { on = true } })
    http.assert_sent_json(rest, "PUT", LIGHT_PATH .. LIGHT_2_RID, { on = { on = false } })
  end
)

test.register_coroutine_test(
  "commands without a grouped handler are sent individually even for a whole room",
  function()
    init_and_scan_groups()
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
    http.assert_sent_json(rest, "PUT", LIGHT_PATH .. LIGHT_1_RID, { dimming_delta = { action = "up", brightness_delta = 10 } })
  end
)

local function set_level_cmd(level)
  return { capability = "switchLevel", component = "main", command = "setLevel", args = { level } }
end

test.register_coroutine_test(
  "a grouped setLevel for a room that is already on only sends the brightness",
  function()
    -- The lights' init refreshes reported them all on.
    init_and_scan_groups()
    expect_grouped_light_put(GROUPED_LIGHT_RID, { dimming = { brightness = 23 } })

    test.socket.capability:__queue_receive_batch({
      { light_1.id, set_level_cmd(23) },
      { light_2.id, set_level_cmd(23) },
    })
    test.wait_for_events()

    assert_requests("PUT", GROUPED_LIGHT_PATH .. GROUPED_LIGHT_RID, 1)
    for _, request in ipairs(http.find_requests(rest, "PUT", GROUPED_LIGHT_PATH, { prefix = true })) do
      assert(request.json.on == nil, "expected no on/off request for a room that is already on")
    end
  end
)

test.register_coroutine_test(
  "a grouped setLevel turns the room on first when one of its lights is off",
  function()
    init_and_scan_groups()
    -- The bridge reports light 2 turned off.
    http.queue_sse_event(sse, { hue_test_helpers.light_event(LIGHT_2_RID, false) })
    test.socket.capability:__expect_send(light_2:generate_test_message("main", capabilities.switch.switch.off()))
    test.wait_for_events()

    expect_grouped_light_put(GROUPED_LIGHT_RID, { on = { on = true } })
    expect_grouped_light_put(GROUPED_LIGHT_RID, { dimming = { brightness = 23 } })

    test.socket.capability:__queue_receive_batch({
      { light_1.id, set_level_cmd(23) },
      { light_2.id, set_level_cmd(23) },
    })
    test.wait_for_events()

    assert_requests("PUT", GROUPED_LIGHT_PATH .. GROUPED_LIGHT_RID, 2)
  end
)

test.register_coroutine_test(
  "a grouped setLevel turns the room on first when a light's state is not known yet",
  function()
    init_and_scan_groups()
    -- A light's switch state is unknown when the bridge has never reported it, e.g. when its
    -- refreshes failed. Every light's init refresh here succeeds, so the driver's record of light
    -- 2's state is cleared directly instead.
    fixtures.driver_device(light_2):set_field(Fields.SWITCH_STATE, nil, { persist = true })
    expect_grouped_light_put(GROUPED_LIGHT_RID, { on = { on = true } })
    expect_grouped_light_put(GROUPED_LIGHT_RID, { dimming = { brightness = 23 } })

    test.socket.capability:__queue_receive_batch({
      { light_1.id, set_level_cmd(23) },
      { light_2.id, set_level_cmd(23) },
    })
    test.wait_for_events()

    assert_requests("PUT", GROUPED_LIGHT_PATH .. GROUPED_LIGHT_RID, 2)
  end
)

test.register_coroutine_test(
  "a batch covering every light in a zone is sent as one grouped_light request",
  function()
    init_and_scan_groups()
    expect_grouped_light_put(ZONE_GROUPED_LIGHT_RID, { on = { on = false } })

    test.socket.capability:__queue_receive_batch({
      { light_4.id, switch_cmd("off") },
      { light_5.id, switch_cmd("off") },
    })
    test.wait_for_events()

    assert_requests("PUT", GROUPED_LIGHT_PATH .. ZONE_GROUPED_LIGHT_RID, 1)
    assert_requests("PUT", LIGHT_PATH, 0)
  end
)

test.register_coroutine_test(
  "a room containing a device the driver doesn't know is not used to group commands",
  function()
    init_and_scan_groups()
    -- Light 3 is the only light of its room the driver has, but the room also holds an unknown
    -- device, so a grouped request for it could change that device too.
    expect_light_put(LIGHT_3_RID, { on = { on = true } })

    test.socket.capability:__queue_receive_batch({ { light_3.id, switch_cmd("on") } })
    test.wait_for_events()

    assert_requests("PUT", LIGHT_PATH .. LIGHT_3_RID, 1)
    assert_requests("PUT", GROUPED_LIGHT_PATH, 0)
  end
)

--- Run `fn`, returning the messages logged with `log.error_with` while it ran.
local function capture_logged_errors(fn)
  local log = require "log"
  local original = log.error_with
  local messages = {}
  log.error_with = function(opts, ...)
    table.insert(messages, table.concat({ ... }, " "))
    return original(opts, ...)
  end
  local ok, err = pcall(fn)
  log.error_with = original
  if not ok then error(err, 0) end
  return messages
end

test.register_coroutine_test(
  "errors the bridge returns for a grouped command are logged",
  function()
    init_and_scan_groups()
    http.expect_request_for_test(rest, "PUT", GROUPED_LIGHT_PATH .. GROUPED_LIGHT_RID, {
      status = 503,
      body = { errors = { { description = "bridge is busy" } }, data = {} },
    })

    local messages = capture_logged_errors(function()
      test.socket.capability:__queue_receive_batch({
        { light_1.id, switch_cmd("on") },
        { light_2.id, switch_cmd("on") },
      })
      test.wait_for_events()
    end)

    assert_requests("PUT", GROUPED_LIGHT_PATH .. GROUPED_LIGHT_RID, 1)
    local logged = false
    for _, message in ipairs(messages) do
      if message:find("bridge is busy", 1, true) then logged = true end
    end
    assert(logged, "expected the bridge's error to be logged, got: " .. table.concat(messages, " | "))
  end
)

test.run_registered_tests()
