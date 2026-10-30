-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- The Sonos messages exchanged over an online player's websocket: what the player pushes becomes
--- capability events, and capability commands become messages to the player or its group.

-- These tests use the integration test framework's LAN support, new in lua_libs API version 23.
-- With older lua_libs, skip the file rather than fail loading it.
if require("version").api < 23 then return end

local test = require "integration_test"
local capabilities = require "st.capabilities"
local helpers = require "test.sonos_test_helpers"
local http = require "integration_test.connection_scenario_http"

local fixture = helpers.new_fixture()
test.set_test_init_function(fixture.test_init)

local function receive_command(capability, command, args)
  test.socket.capability:__queue_receive({
    fixture.device.id,
    { capability = capability, command = command, args = args or {}, component = "main" },
  })
end

test.register_coroutine_test(
  "a playbackStatus push emits the group's playback status",
  function()
    fixture.bring_up()
    fixture.expect_event(capabilities.mediaPlayback.playbackStatus.playing())
    fixture.ws:queue_bytes(helpers.ws_json(helpers.push_header("playbackStatus"), { playbackState = "PLAYBACK_STATE_PLAYING" }))
    test.wait_for_events()
    fixture.expect_event(capabilities.mediaPlayback.playbackStatus.paused())
    fixture.ws:queue_bytes(helpers.ws_json(helpers.push_header("playbackStatus"), { playbackState = "PLAYBACK_STATE_PAUSED" }))
    test.wait_for_events()
  end,
  { min_api_version = 23 }
)

test.register_coroutine_test(
  "a playerVolume push emits the player's volume and mute state",
  function()
    fixture.bring_up()
    fixture.expect_event(capabilities.audioVolume.volume(35))
    fixture.expect_event(capabilities.audioMute.mute.unmuted())
    fixture.ws:queue_bytes(helpers.ws_json(helpers.push_header("playerVolume"), { volume = 35, muted = false }))
    test.wait_for_events()
  end,
  { min_api_version = 23 }
)

test.register_coroutine_test(
  "a groupVolume push that arrives in two TCP segments emits the group's volume and mute state",
  function()
    fixture.bring_up()
    fixture.expect_event(capabilities.mediaGroup.groupVolume(12))
    fixture.expect_event(capabilities.mediaGroup.groupMute.muted())
    local frame = helpers.ws_json(helpers.push_header("groupVolume"), { volume = 12, muted = true })
    fixture.ws:queue_bytes(frame:sub(1, 10))
    test.wait_for_events()
    fixture.ws:queue_bytes(frame:sub(11))
    test.wait_for_events()
  end,
  { min_api_version = 23 }
)

test.register_coroutine_test(
  "a playbackStatus push of IDLE emits stopped",
  function()
    fixture.bring_up()
    fixture.expect_event(capabilities.mediaPlayback.playbackStatus.stopped())
    fixture.ws:queue_bytes(helpers.ws_json(helpers.push_header("playbackStatus"), { playbackState = "PLAYBACK_STATE_IDLE" }))
    test.wait_for_events()
  end,
  { min_api_version = 23 }
)

test.register_coroutine_test(
  "a metadataStatus push emits the track's data and its source",
  function()
    fixture.bring_up()
    fixture.expect_event(capabilities.audioTrackData.audioTrackData({
      title = "Song", artist = "Singer", album = "Record", mediaSource = "Radio X",
    }))
    fixture.ws:queue_bytes(helpers.ws_json(helpers.push_header("metadataStatus"), {
      container = { type = "station", name = "Radio X" },
      currentItem = { track = { name = "Song", artist = { name = "Singer" }, album = { name = "Record" } } },
    }))
    test.wait_for_events()
  end,
  { min_api_version = 23 }
)

test.register_coroutine_test(
  "a playerVolume push about another player is ignored",
  function()
    fixture.bring_up()
    fixture.ws:queue_bytes(helpers.ws_json(
      helpers.push_header("playerVolume", { playerId = "RINCON_11223344556601400" }), { volume = 80, muted = true }))
    test.wait_for_events()
    -- Pushes are handled in order, so once this one is emitted the other has been dealt with.
    fixture.expect_event(capabilities.audioVolume.volume(35))
    fixture.expect_event(capabilities.audioMute.mute.unmuted())
    fixture.ws:queue_bytes(helpers.ws_json(helpers.push_header("playerVolume"), { volume = 35, muted = false }))
    test.wait_for_events()
  end,
  { min_api_version = 23 }
)

test.register_coroutine_test(
  "a favorites versionChanged push makes the driver fetch the favorites and emit them as presets",
  function()
    fixture.bring_up()
    http.expect_request(fixture.rest, "GET", "/api/v1/households/" .. helpers.HOUSEHOLD .. "/favorites", {
      body = { items = { { id = "fav1", name = "Morning Jazz", service = { name = "Spotify" } } } },
    })
    fixture.expect_event(capabilities.mediaPresets.presets({ { id = "fav1", name = "Morning Jazz", mediaSource = "Spotify" } }))
    fixture.ws:queue_bytes(helpers.ws_json(helpers.push_header("versionChanged", { namespace = "favorites" }), { version = "2" }))
    test.wait_for_events()
  end,
  { min_api_version = 23 }
)

test.register_coroutine_test(
  "a refresh command subscribes to the player's and its group's namespaces again",
  function()
    fixture.bring_up()
    receive_command("refresh", "refresh")
    test.wait_until(function() return #helpers.sent_ws_messages(fixture.ws, 1) == 14 end,
      { within = 10, message = "7 more subscribe frames" })
    for _, message in ipairs(helpers.sent_ws_messages(fixture.ws, 1)) do
      assert(message.header.command == "subscribe", "expected only subscribe commands, got " .. tostring(message.header.command))
    end
    assert(fixture.ws:connection_count() == 1, "a refresh should reuse the websocket connection")
  end,
  { min_api_version = 23 }
)

-- A capability command becomes a Sonos message in `namespace`, addressed in its header to the
-- player itself (`to = "player"`) or to its group.
local commands = {
  { cap = "audioVolume", command = "setVolume", args = { 25 }, to = "player", namespace = "playerVolume", sonos = "setVolume", body = { volume = 25 } },
  { cap = "audioVolume", command = "volumeUp", to = "player", namespace = "playerVolume", sonos = "setRelativeVolume", body = { volumeDelta = 5 } },
  { cap = "audioVolume", command = "volumeDown", to = "player", namespace = "playerVolume", sonos = "setRelativeVolume", body = { volumeDelta = -5 } },
  { cap = "audioMute", command = "mute", to = "player", namespace = "playerVolume", sonos = "setMute", body = { muted = true } },
  { cap = "audioMute", command = "unmute", to = "player", namespace = "playerVolume", sonos = "setMute", body = { muted = false } },
  { cap = "audioMute", command = "setMute", args = { "muted" }, to = "player", namespace = "playerVolume", sonos = "setMute", body = { muted = true } },
  { cap = "mediaGroup", command = "setGroupVolume", args = { 40 }, to = "group", namespace = "groupVolume", sonos = "setVolume", body = { volume = 40 } },
  { cap = "mediaGroup", command = "muteGroup", to = "group", namespace = "groupVolume", sonos = "setMute", body = { muted = true } },
  { cap = "mediaGroup", command = "groupVolumeUp", to = "group", namespace = "groupVolume", sonos = "setRelativeVolume", body = { volumeDelta = 5 } },
  { cap = "mediaPlayback", command = "play", to = "group", namespace = "playback", sonos = "play" },
  { cap = "mediaPlayback", command = "pause", to = "group", namespace = "playback", sonos = "pause" },
  { cap = "mediaPlayback", command = "stop", to = "group", namespace = "playback", sonos = "pause" },
  { cap = "mediaTrackControl", command = "nextTrack", to = "group", namespace = "playback", sonos = "skipToNextTrack" },
  { cap = "mediaTrackControl", command = "previousTrack", to = "group", namespace = "playback", sonos = "skipToPreviousTrack" },
  { cap = "mediaPresets", command = "playPreset", args = { "fav1" }, to = "group", namespace = "favorites", sonos = "loadFavorite",
    body = { favoriteId = "fav1", playOnCompletion = true } },
  { cap = "audioNotification", command = "playTrack", args = { "https://example.com/chime.mp3", 30 }, to = "player",
    namespace = "audioClip", sonos = "loadAudioClip", body = { streamUrl = "https://example.com/chime.mp3", volume = 30 } },
}

for _, case in ipairs(commands) do
  test.register_coroutine_test(
    string.format("a %s command is sent as %s.%s", case.command, case.namespace, case.sonos),
    function()
      fixture.bring_up()
      local header = { householdId = helpers.HOUSEHOLD }
      if case.to == "player" then
        header.playerId = helpers.PLAYER_ID
      else
        header.groupId = helpers.GROUP_ID
      end
      helpers.expect_ws_message(fixture.ws, case.namespace, case.sonos, { header = header, body = case.body })
      receive_command(case.cap, case.command, case.args)
      test.wait_for_events()
    end,
    { min_api_version = 23 }
  )
end

test.run_registered_tests()
