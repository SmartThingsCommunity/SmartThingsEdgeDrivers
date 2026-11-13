-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- Sonos groups: a player that is not its group's coordinator holds a websocket of its own and
--- one to its coordinator, sends group commands over the coordinator's and player commands over
--- its own, and follows the group when the household's topology changes.

-- These tests use the integration test framework's LAN support, new in lua_libs API version 23.
-- With older lua_libs, skip the file rather than fail loading it.
if require("version").api < 23 then return end

local test = require "integration_test"
local capabilities = require "st.capabilities"
local helpers = require "test.sonos_test_helpers"
local http = require "integration_test.connection_scenario_http"

--#region The household: three players on three addresses

local HOUSEHOLD = helpers.HOUSEHOLD

local function new_player(name, ip, mac)
  local id = "RINCON_" .. mac .. "01400"
  local serial = mac:gsub("(%x%x)", "%1-"):sub(1, -2) .. ":1"
  local scenario, rest, ws = helpers.create_scenario(ip)
  return {
    name = name, ip = ip, mac = mac, id = id, serial = serial,
    scenario = scenario, rest = rest, ws = ws,
    device = test.mock_device.build_test_lan_device({
      profile = helpers.profile(), device_network_id = mac, label = name,
    }),
  }
end

local kitchen = new_player("Kitchen", "192.168.1.50", "AABBCCDDEEFF")
local office = new_player("Office", "192.168.1.51", "112233445566")
local den = new_player("Den", "192.168.1.52", "665544332211")
local players = { kitchen, office, den }

local function ws_url(player)
  return string.format("wss://%s:%d/websocket/api", player.ip, helpers.PLAYER_PORT)
end

--- A group of the household: `coordinator` and the `members` (a list that holds it).
local function group(id, coordinator, members)
  return { id = id, coordinator = coordinator, members = members }
end

--- The body of a Sonos `groups` response (and push) for the given groups.
local function groups_body(groups)
  local body = { _objectType = "groups", groups = {}, players = {} }
  for _, g in ipairs(groups) do
    local ids = {}
    for _, member in ipairs(g.members) do
      table.insert(ids, member.id)
      table.insert(body.players, {
        id = member.id, name = member.name, websocketUrl = ws_url(member), devices = { { id = member.id } },
      })
    end
    table.insert(body.groups, {
      id = g.id, name = g.coordinator.name, coordinatorId = g.coordinator.id,
      playbackState = "PLAYBACK_STATE_IDLE", playerIds = ids,
    })
  end
  return body
end

--- A player's reply to the driver's SSDP search: it names the player's group and whether it
--- coordinates it.
local function ssdp_reply(player, g)
  return table.concat({
    "HTTP/1.1 200 OK",
    "CACHE-CONTROL: max-age = 1800",
    "EXT:",
    string.format("LOCATION: http://%s:1400/xml/device_description.xml", player.ip),
    "SERVER: Linux UPnP/1.0 Sonos/70.3-88200 (ZPS9)",
    "ST: " .. helpers.SEARCH_TERM,
    string.format("USN: uuid:%s::%s", player.id, helpers.SEARCH_TERM),
    "HOUSEHOLD.SMARTSPEAKER.AUDIO: " .. HOUSEHOLD,
    string.format('GROUPINFO.SMARTSPEAKER.AUDIO: gc=%d; gid=%s; gname="%s"',
      g.coordinator == player and 1 or 0, g.id, g.coordinator.name),
    string.format("WEBSOCK.SMARTSPEAKER.AUDIO: %s", ws_url(player)),
    "", "",
  }, "\r\n")
end

local function player_info(player)
  return {
    _objectType = "playerInfo",
    playerId = player.id,
    websocketUrl = ws_url(player),
    restUrl = string.format("https://%s:%d/api/v1", player.ip, helpers.PLAYER_PORT),
    householdId = HOUSEHOLD,
    device = {
      id = player.id, name = player.name, model = "sonos-one", modelDisplayName = "Sonos One",
      serialNumber = player.serial, swGen = 2, primaryDeviceId = player.id,
    },
  }
end

local ssdp = test.mock_lan_socket.udp_peer("239.255.255.250", 1900)

--- What every player answers on its connections in every test, except for its groups, which
--- `set_topology` has each test choose: its info, the websocket upgrade and the subscriptions.
for _, player in ipairs(players) do
  http.expect_request(player.rest, "GET", "/api/v1/players/local/info", { body = player_info(player), reusable = true })
  player.ws:expect({
    request = { pattern = "^GET /websocket/api" },
    description = "websocket upgrade",
    responses = { { generator = helpers.upgrade_response } },
    reusable = true,
  })
  player.ws:expect({ request = { pattern = "^WS close" }, description = "websocket close frame", responses = {}, reusable = true })
  for _, namespaces in ipairs({ helpers.PLAYER_SUBSCRIPTIONS, helpers.GROUP_SUBSCRIPTIONS }) do
    for _, namespace in ipairs(namespaces) do
      helpers.expect_ws_message(player.ws, namespace, "subscribe", { reusable = true })
    end
  end
end

--- Choose the household's groups, as the players report them over REST.
local function set_topology(groups)
  for _, player in ipairs(players) do
    http.expect_request(player.rest, "GET", "/api/v1/households/" .. HOUSEHOLD .. "/groups",
      { body = groups_body(groups), reusable = true })
  end
end

--#endregion

--#region Fixture

local function unload_driver_modules()
  local names = {}
  for name in pairs(package.loaded) do
    if not name:match("^test%.") and not name:match("^cosock") and name ~= "init" then
      local found = package.searchpath(name, package.path)
      if found and found:sub(1, 2) == "./" then table.insert(names, name) end
    end
  end
  for _, name in ipairs(names) do package.loaded[name] = nil end
end

local function expect_event(device, event)
  test.socket.capability:__expect_send(device:generate_test_message("main", event))
end

--- The test_init for a hub that has a device for each of `with_devices`.
local function init_with(with_devices)
  return function()
    unload_driver_modules()
    for _, player in ipairs(players) do player.scenario:activate() end
    test.socket.capability:__set_channel_ordering("relaxed")
    for _, player in ipairs(with_devices) do
      test.mock_device.add_test_device(player.device)
      expect_event(player.device, capabilities.mediaPlayback.supportedPlaybackCommands({ "play", "pause", "stop" }))
      expect_event(player.device, capabilities.mediaTrackControl.supportedTrackControlCommands({ "nextTrack", "previousTrack" }))
    end
  end
end

local function is_online(player)
  return test.mock_devices_api.__is_device_online(player.device.id)
end

--- A player's group role in `g`, as the driver reports it.
local function role_in(player, g)
  if g.coordinator ~= player then return "auxilary" end
  return #g.members > 1 and "primary" or "ungrouped"
end

--- Expect what a device emits when the driver has read its player's info and groups.
local function expect_player_events(player, g)
  expect_event(player.device, capabilities["stus.softwareGeneration"].generation("2"))
  expect_event(player.device, capabilities.mediaGroup.groupRole(role_in(player, g)))
  expect_event(player.device, capabilities.mediaGroup.groupPrimaryDeviceId(g.coordinator.id))
end

--- Bring the players up one after the other, each in its group, and wait for each device to
--- be online. A player without a device is not brought up: only its websocket is opened, by the
--- members of its group.
--- @param entries table[] `{ player, group }` in the order the players answer the search
local function bring_up(entries)
  for _, entry in ipairs(entries) do
    local player, g = entry[1], entry[2]
    expect_player_events(player, g)
    test.wait_until(function() return #ssdp:sent() > 0 end, { within = 10, message = "the driver's M-SEARCH" })
    ssdp:reply(ssdp_reply(player, g), { from_host = player.ip })
    test.wait_until(function() return is_online(player) end, { within = 30, message = player.name .. " online" })
    test.wait_for_events()
  end
end

--#endregion

--#region Helpers for the tests

local function receive_command(player, capability, command, args)
  test.socket.capability:__queue_receive({
    player.device.id,
    { capability = capability, command = command, args = args or {}, component = "main" },
  })
end

--- Push a `groups` message (the household's new groups) to the driver over a player's websocket.
local function push_groups(player, groups)
  player.ws:queue_bytes(helpers.ws_json(
    { namespace = "groups", type = "groups", householdId = HOUSEHOLD }, groups_body(groups)))
end

--- Push a message about a group over a player's websocket, as the player's group coordinator does.
local function push_group_message(player, type_, g, body)
  player.ws:queue_bytes(helpers.ws_json(
    helpers.push_header(type_, { groupId = g.id, playerId = g.coordinator.id }), body))
end

--- The Sonos messages the driver sent on a player's (newest) websocket in `namespace`.
local function sent_in(player, namespace, command)
  local found = {}
  for _, message in ipairs(helpers.sent_ws_messages(player.ws)) do
    if message.header.namespace == namespace and (command == nil or message.header.command == command) then
      table.insert(found, message)
    end
  end
  return found
end

--- Whether the driver closed the websocket to `player` (it sends a Close frame).
local function sent_close(player)
  for _, frame in ipairs(helpers.sent_ws_frames(player.ws)) do
    if frame.opcode == 0x8 then return true end
  end
  return false
end

--- The subscriptions the driver made on `player`'s websocket (the newest connection) as
--- "namespace for player in group" strings, one per message.
local function subscriptions_on(player)
  local found = {}
  for _, message in ipairs(helpers.sent_ws_messages(player.ws)) do
    assert(message.header.command == "subscribe", "expected only subscribe commands on " .. player.name
      .. "'s websocket, got " .. tostring(message.header.command))
    table.insert(found, string.format("%s %s %s", message.header.namespace, message.header.playerId, message.header.groupId))
  end
  table.sort(found)
  return found
end

--- What subscribing to `namespaces` once, for `player` in group `g`, looks like.
local function subscribe_messages(namespaces, player, g)
  local expected = {}
  for _, namespace in ipairs(namespaces) do
    table.insert(expected, string.format("%s %s %s", namespace, player.id, g.id))
  end
  table.sort(expected)
  return expected
end

local function assert_same_list(actual, expected, what)
  assert(table.concat(actual, "\n") == table.concat(expected, "\n"), string.format(
    "%s\nexpected:\n  %s\ngot:\n  %s", what, table.concat(expected, "\n  "), table.concat(actual, "\n  ")))
end

--- Wait for the driver to have sent `command` in `namespace` on `player`'s websocket.
local function await_sent(player, namespace, command)
  test.wait_until(function() return #sent_in(player, namespace, command) > 0 end,
    { within = 10, message = string.format("%s.%s on %s's websocket", namespace, command, player.name) })
end

local function expect_events(player, ...)
  for _, event in ipairs({ ... }) do expect_event(player.device, event) end
end

--#endregion

local solo_kitchen = group(kitchen.id .. ":1", kitchen, { kitchen })
local solo_office = group(office.id .. ":1", office, { office })
local kitchen_pair = group(kitchen.id .. ":2", kitchen, { kitchen, office })


local function assert_includes(actual, expected, what)
  local have = {}
  for _, item in ipairs(actual) do have[item] = true end
  for _, item in ipairs(expected) do
    assert(have[item], string.format("%s: missing '%s' in\n  %s", what, item, table.concat(actual, "\n  ")))
  end
end

local PLAYER_NAMESPACES, COORDINATOR_NAMESPACES = helpers.PLAYER_SUBSCRIPTIONS, helpers.GROUP_SUBSCRIPTIONS
local mediaGroup = capabilities.mediaGroup

--#region Bringing a member up

test.register_coroutine_test(
  "a player in another player's group opens a websocket to its coordinator, even when the coordinator has no device",
  function()
    set_topology({ kitchen_pair })
    bring_up({ { office, kitchen_pair } })

    assert(office.ws:connection_count() == 1, "expected one websocket to the member itself")
    assert(kitchen.ws:connection_count() == 1, "expected one websocket to the coordinator")
    -- The member subscribes to its own namespaces on its own websocket, and to its group's on
    -- the coordinator's, naming the coordinator as the player.
    assert_same_list(subscriptions_on(office), subscribe_messages(PLAYER_NAMESPACES, office, kitchen_pair),
      "subscriptions on the member's websocket")
    assert_same_list(subscriptions_on(kitchen), subscribe_messages(COORDINATOR_NAMESPACES, kitchen, kitchen_pair),
      "subscriptions on the coordinator's websocket")
  end,
  { min_api_version = 23, test_init = init_with({ office }) }
)

--#endregion

--#region Commands

local function group_command_cases()
  return {
    { "mediaPlayback", "play", nil, "playback", "play" },
    { "mediaPlayback", "pause", nil, "playback", "pause" },
    { "mediaTrackControl", "nextTrack", nil, "playback", "skipToNextTrack" },
    { "mediaGroup", "setGroupVolume", { 40 }, "groupVolume", "setVolume" },
    { "mediaGroup", "muteGroup", nil, "groupVolume", "setMute" },
    { "mediaPresets", "playPreset", { "fav1" }, "favorites", "loadFavorite" },
  }
end

test.register_coroutine_test(
  "a member's group commands are sent over its coordinator's websocket, not its own",
  function()
    set_topology({ kitchen_pair })
    bring_up({ { office, kitchen_pair } })
    local sent_on_office = #helpers.sent_ws_messages(office.ws)

    for _, case in ipairs(group_command_cases()) do
      helpers.expect_ws_message(kitchen.ws, case[4], case[5], { header = { householdId = HOUSEHOLD, groupId = kitchen_pair.id } })
      receive_command(office, case[1], case[2], case[3])
      await_sent(kitchen, case[4], case[5])
    end
    assert(#helpers.sent_ws_messages(office.ws) == sent_on_office, "the member's own websocket should have carried nothing more")
  end,
  { min_api_version = 23, test_init = init_with({ office }) }
)

test.register_coroutine_test(
  "a member's player commands are sent over its own websocket, not its coordinator's",
  function()
    set_topology({ kitchen_pair })
    bring_up({ { office, kitchen_pair } })
    local sent_on_kitchen = #helpers.sent_ws_messages(kitchen.ws)

    helpers.expect_ws_message(office.ws, "playerVolume", "setVolume",
      { header = { householdId = HOUSEHOLD, playerId = office.id }, body = { volume = 25 } })
    receive_command(office, "audioVolume", "setVolume", { 25 })
    await_sent(office, "playerVolume", "setVolume")

    helpers.expect_ws_message(office.ws, "playerVolume", "setMute",
      { header = { householdId = HOUSEHOLD, playerId = office.id }, body = { muted = true } })
    receive_command(office, "audioMute", "mute")
    await_sent(office, "playerVolume", "setMute")

    helpers.expect_ws_message(office.ws, "audioClip", "loadAudioClip",
      { header = { householdId = HOUSEHOLD, playerId = office.id } })
    receive_command(office, "audioNotification", "playTrack", { "https://example.com/chime.mp3" })
    await_sent(office, "audioClip", "loadAudioClip")

    assert(#helpers.sent_ws_messages(kitchen.ws) == sent_on_kitchen, "the coordinator's websocket should have carried nothing more")
  end,
  { min_api_version = 23, test_init = init_with({ office }) }
)

--#endregion

--#region Pushes about a group

test.register_coroutine_test(
  "a group's pushes on its coordinator's websocket reach a member whose coordinator has no device",
  function()
    set_topology({ kitchen_pair })
    bring_up({ { office, kitchen_pair } })

    expect_events(office, mediaGroup.groupVolume(12), mediaGroup.groupMute.muted())
    push_group_message(kitchen, "groupVolume", kitchen_pair, { volume = 12, muted = true })
    test.wait_for_events()

    expect_events(office, capabilities.mediaPlayback.playbackStatus.playing())
    push_group_message(kitchen, "playbackStatus", kitchen_pair, { playbackState = "PLAYBACK_STATE_PLAYING" })
    test.wait_for_events()
  end,
  { min_api_version = 23, test_init = init_with({ office }) }
)

test.register_coroutine_test(
  "a group's pushes are emitted by the devices of every player in that group, and by no others",
  function()
    set_topology({ kitchen_pair })
    bring_up({ { kitchen, kitchen_pair }, { office, kitchen_pair } })

    for _, player in ipairs({ kitchen, office }) do
      expect_events(player, mediaGroup.groupVolume(30), mediaGroup.groupMute.unmuted())
    end
    push_group_message(kitchen, "groupVolume", kitchen_pair, { volume = 30, muted = false })
    test.wait_for_events()

    for _, player in ipairs({ kitchen, office }) do
      expect_events(player, capabilities.mediaPlayback.playbackStatus.paused())
    end
    push_group_message(kitchen, "playbackStatus", kitchen_pair, { playbackState = "PLAYBACK_STATE_PAUSED" })
    test.wait_for_events()

    -- A push about a group the household doesn't have is ignored; the next one is emitted once
    -- it has been dealt with.
    push_group_message(kitchen, "groupVolume", group(den.id .. ":9", den, { den }), { volume = 99, muted = true })
    test.wait_for_events()
    for _, player in ipairs({ kitchen, office }) do
      expect_events(player, mediaGroup.groupVolume(31), mediaGroup.groupMute.unmuted())
    end
    push_group_message(kitchen, "groupVolume", kitchen_pair, { volume = 31, muted = false })
    test.wait_for_events()
  end,
  { min_api_version = 23, test_init = init_with({ kitchen, office }) }
)

--#endregion

--#region Changes to the groups

--- Let the driver run on long enough to have closed any websocket it meant to close: the
--- router's task acts on those between its waits, which last up to ten seconds.
local function let_router_settle()
  test.let_time_pass(30)
end

test.register_coroutine_test(
  "a groups push that changes nothing leaves the websockets, subscriptions and events alone",
  function()
    set_topology({ kitchen_pair })
    bring_up({ { office, kitchen_pair } })
    test.mock_devices_api.__clear_device_status_history()
    local frames_on_office, frames_on_kitchen = #helpers.sent_ws_frames(office.ws), #helpers.sent_ws_frames(kitchen.ws)

    push_groups(office, { kitchen_pair })
    test.wait_for_events()
    let_router_settle()

    assert(not sent_close(kitchen), "the coordinator's websocket is still in use and should stay open")
    assert(not sent_close(office), "the member's own websocket should stay open")
    assert(#test.mock_devices_api.__get_device_status_history(office.device.id) == 0, "the device's status should not change")
    assert(#helpers.sent_ws_frames(office.ws) == frames_on_office, "nothing should be subscribed to again")
    assert(#helpers.sent_ws_frames(kitchen.ws) == frames_on_kitchen, "nothing should be subscribed to again")
    assert(kitchen.ws:connection_count() == 1 and office.ws:connection_count() == 1, "no websocket should be opened again")
  end,
  { min_api_version = 23, test_init = init_with({ office }) }
)

test.register_coroutine_test(
  "dissolving the group closes the coordinator's websocket that no device needs and moves the group commands to the player's own",
  function()
    set_topology({ kitchen_pair })
    bring_up({ { office, kitchen_pair } })

    local office_alone, kitchen_alone = group(office.id .. ":3", office, { office }), group(kitchen.id .. ":3", kitchen, { kitchen })
    expect_events(office, mediaGroup.groupId(office_alone.id), mediaGroup.groupRole("ungrouped"),
      mediaGroup.groupPrimaryDeviceId(office.id))
    push_groups(office, { office_alone, kitchen_alone })
    test.wait_for_events()
    test.wait_until(function() return sent_close(kitchen) end, { within = 30, message = "the driver closing the coordinator's websocket" })
    let_router_settle()

    assert(not sent_close(office), "the member's own websocket is still in use and should stay open")
    assert(kitchen.ws:connection_count() == 1, "the old coordinator's websocket should not be opened again")
    -- It now subscribes to its group's namespaces on its own websocket.
    assert_includes(subscriptions_on(office), subscribe_messages(COORDINATOR_NAMESPACES, office, office_alone),
      "subscriptions on the member's websocket")
    assert(test.mock_devices_api.__is_device_online(office.device.id), "the device should be online")

    helpers.expect_ws_message(office.ws, "playback", "play", { header = { groupId = office_alone.id } })
    receive_command(office, "mediaPlayback", "play")
    await_sent(office, "playback", "play")
  end,
  { min_api_version = 23, test_init = init_with({ office }) }
)

test.register_coroutine_test(
  "a coordinator's websocket stays open while another device's group still uses it",
  function()
    local kitchen_trio = group(kitchen.id .. ":2", kitchen, { kitchen, office, den })
    set_topology({ kitchen_trio })
    bring_up({ { office, kitchen_trio }, { den, kitchen_trio } })

    -- The office leaves; the den stays with the kitchen, which has no device.
    local kitchen_and_den = group(kitchen.id .. ":2", kitchen, { kitchen, den })
    local office_alone = group(office.id .. ":3", office, { office })
    expect_events(office, mediaGroup.groupId(office_alone.id), mediaGroup.groupRole("ungrouped"),
      mediaGroup.groupPrimaryDeviceId(office.id))
    push_groups(office, { kitchen_and_den, office_alone })
    test.wait_for_events()
    let_router_settle()

    assert(not sent_close(kitchen), "the den's coordinator websocket should stay open")
  end,
  { min_api_version = 23, test_init = init_with({ office, den }) }
)

test.register_coroutine_test(
  "a group that moves to a coordinator the driver has no websocket for opens one and keeps the players' own",
  function()
    set_topology({ kitchen_pair })
    bring_up({ { kitchen, kitchen_pair }, { office, kitchen_pair } })

    -- The den, which has no device, takes over the group.
    local den_trio = group(den.id .. ":1", den, { den, kitchen, office })
    for _, player in ipairs({ kitchen, office }) do
      expect_events(player, mediaGroup.groupId(den_trio.id), mediaGroup.groupPrimaryDeviceId(den.id))
    end
    expect_events(kitchen, mediaGroup.groupRole("auxilary"))
    push_groups(kitchen, { den_trio })
    push_groups(office, { den_trio })
    test.wait_until(function() return den.ws:connection_count() == 1 end, { within = 30, message = "a websocket to the new coordinator" })
    test.wait_for_events()
    let_router_settle()

    assert(den.ws:connection_count() == 1, "expected exactly one websocket to the new coordinator, for both players")
    assert(not sent_close(kitchen) and not sent_close(office), "both players still have a device and keep their websocket")
    assert_includes(subscriptions_on(den), subscribe_messages(COORDINATOR_NAMESPACES, den, den_trio),
      "subscriptions on the new coordinator's websocket")

    -- Group commands from both go to the den now.
    helpers.expect_ws_message(den.ws, "playback", "pause", { header = { groupId = den_trio.id }, reusable = true })
    receive_command(office, "mediaPlayback", "pause")
    test.wait_until(function() return #sent_in(den, "playback", "pause") == 1 end, { within = 10, message = "the office's pause on the den's websocket" })
    receive_command(kitchen, "mediaPlayback", "pause")
    test.wait_until(function() return #sent_in(den, "playback", "pause") == 2 end, { within = 10, message = "the kitchen's pause on the den's websocket" })
    assert(#sent_in(kitchen, "playback", "pause") == 0, "the old coordinator should get no more group commands")

    -- The group's pushes on the den's websocket are emitted once by each of the two devices.
    for _, player in ipairs({ kitchen, office }) do
      expect_events(player, mediaGroup.groupVolume(8), mediaGroup.groupMute.muted())
    end
    push_group_message(den, "groupVolume", den_trio, { volume = 8, muted = true })
    test.wait_for_events()
  end,
  { min_api_version = 23, test_init = init_with({ kitchen, office }) }
)

test.register_coroutine_test(
  "a group that moves to another coordinator closes the old coordinator's websocket when no device needs it, and opens the new one",
  function()
    set_topology({ kitchen_pair })
    bring_up({ { office, kitchen_pair } })

    -- The den takes the office into its group; the kitchen is alone.
    local den_pair, kitchen_alone = group(den.id .. ":1", den, { den, office }), group(kitchen.id .. ":3", kitchen, { kitchen })
    expect_events(office, mediaGroup.groupId(den_pair.id), mediaGroup.groupPrimaryDeviceId(den.id))
    push_groups(office, { den_pair, kitchen_alone })
    test.wait_until(function() return den.ws:connection_count() == 1 end, { within = 30, message = "a websocket to the new coordinator" })
    test.wait_until(function() return sent_close(kitchen) end, { within = 30, message = "the old coordinator's websocket being closed" })
    let_router_settle()

    assert(den.ws:connection_count() == 1, "expected exactly one websocket to the new coordinator")
    assert_includes(subscriptions_on(den), subscribe_messages(COORDINATOR_NAMESPACES, den, den_pair),
      "subscriptions on the new coordinator's websocket")
    assert(test.mock_devices_api.__is_device_online(office.device.id), "the device should be online")

    helpers.expect_ws_message(den.ws, "playback", "pause", { header = { groupId = den_pair.id } })
    receive_command(office, "mediaPlayback", "pause")
    await_sent(den, "playback", "pause")
    assert(#sent_in(kitchen, "playback", "pause") == 0, "the old coordinator should get no more commands")
  end,
  { min_api_version = 23, test_init = init_with({ office }) }
)

test.register_coroutine_test(
  "players that form a group emit their new roles and group, and send group commands to the coordinator",
  function()
    set_topology({ solo_kitchen, solo_office })
    bring_up({ { kitchen, solo_kitchen }, { office, solo_office } })

    -- The office joins the kitchen's group. Every player's websocket reports it.
    expect_events(kitchen, mediaGroup.groupId(kitchen_pair.id), mediaGroup.groupRole("primary"))
    expect_events(office, mediaGroup.groupId(kitchen_pair.id), mediaGroup.groupRole("auxilary"),
      mediaGroup.groupPrimaryDeviceId(kitchen.id))
    push_groups(kitchen, { kitchen_pair })
    push_groups(office, { kitchen_pair })
    test.wait_for_events()
    let_router_settle()

    assert(not sent_close(kitchen) and not sent_close(office), "both players still have a device and keep their websocket")
    assert_includes(subscriptions_on(kitchen), subscribe_messages(COORDINATOR_NAMESPACES, kitchen, kitchen_pair),
      "subscriptions on the coordinator's websocket")

    helpers.expect_ws_message(kitchen.ws, "playback", "play", { header = { groupId = kitchen_pair.id } })
    receive_command(office, "mediaPlayback", "play")
    await_sent(kitchen, "playback", "play")
  end,
  { min_api_version = 23, test_init = init_with({ kitchen, office }) }
)

test.register_coroutine_test(
  "when a group's coordinator changes, its players emit the new roles and subscribe to the new coordinator",
  function()
    set_topology({ kitchen_pair })
    bring_up({ { kitchen, kitchen_pair }, { office, kitchen_pair } })
    local office_pair = group(office.id .. ":5", office, { office, kitchen })

    expect_events(office, mediaGroup.groupId(office_pair.id), mediaGroup.groupRole("primary"),
      mediaGroup.groupPrimaryDeviceId(office.id))
    expect_events(kitchen, mediaGroup.groupId(office_pair.id), mediaGroup.groupRole("auxilary"),
      mediaGroup.groupPrimaryDeviceId(office.id))
    push_groups(kitchen, { office_pair })
    push_groups(office, { office_pair })
    test.wait_for_events()
    let_router_settle()

    assert(not sent_close(kitchen) and not sent_close(office), "both players still have a device and keep their websocket")
    -- The kitchen now subscribes to its group's namespaces on the office's websocket.
    assert_includes(subscriptions_on(office), subscribe_messages(COORDINATOR_NAMESPACES, office, office_pair),
      "subscriptions on the new coordinator's websocket")

    -- Group commands now go to the office, from either player; the office's own group
    -- commands are sent on its own websocket as before.
    helpers.expect_ws_message(office.ws, "playback", "play", { header = { groupId = office_pair.id }, reusable = true })
    receive_command(kitchen, "mediaPlayback", "play")
    test.wait_until(function() return #sent_in(office, "playback", "play") == 1 end, { within = 10, message = "the kitchen's play on the office's websocket" })
    receive_command(office, "mediaPlayback", "play")
    test.wait_until(function() return #sent_in(office, "playback", "play") == 2 end, { within = 10, message = "the office's play on its own websocket" })
    assert(#sent_in(kitchen, "playback", "play") == 0, "the old coordinator should get no more group commands")
  end,
  { min_api_version = 23, test_init = init_with({ kitchen, office }) }
)

test.register_coroutine_test(
  "a member whose coordinator was unreachable comes online on a refresh once the coordinator is back",
  function()
    set_topology({ kitchen_pair })
    kitchen.scenario:fail_connects(math.huge, "connection refused")
    expect_player_events(office, kitchen_pair)
    test.wait_until(function() return #ssdp:sent() > 0 end, { within = 10, message = "the driver's M-SEARCH" })
    ssdp:reply(ssdp_reply(office, kitchen_pair), { from_host = office.ip })
    test.wait_until(function() return kitchen.scenario:failed_connect_count() > 0 end,
      { within = 30, message = "an attempt to reach the coordinator" })
    test.wait_for_events()
    assert(not is_online(office), "a member that can't reach its coordinator is not online")

    kitchen.scenario:clear_connect_failures()
    receive_command(office, "refresh", "refresh")
    test.wait_until(function() return is_online(office) end, { within = 30, message = "the device online" })
    test.wait_for_events()
    assert_includes(subscriptions_on(kitchen), subscribe_messages(COORDINATOR_NAMESPACES, kitchen, kitchen_pair),
      "subscriptions on the coordinator's websocket")
  end,
  { min_api_version = 23, test_init = init_with({ office }) }
)

--#endregion

test.run_registered_tests()
