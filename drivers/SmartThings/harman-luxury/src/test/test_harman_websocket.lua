-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- The WebSocket a Harman Luxury speaker keeps open to the driver: what the speaker sends becomes
--- capability events, commands go out over it, and the driver reconnects it (and reports the device
--- offline meanwhile) when the speaker stops answering, closes it, goes away, or hands the speaker
--- to another hub. The speaker is a mock WebSocket server (see harman_test_helpers.lua); the device
--- is one the driver already knew (its address and token persisted), so it connects as soon as it
--- is initialised.

-- These tests use the integration test framework's LAN support, new in lua_libs API version 23.
-- With older lua_libs, skip the file rather than fail loading it.
if require("version").api < 23 then return end

local test = require "integration_test"
local capabilities = require "st.capabilities"
local H = require "test.harman_test_helpers"
local http = require "integration_test.connection_scenario_http"

-- seconds of silence before the driver pings the speaker
local WS_IDLE_PING_PERIOD = require("constants").WS_IDLE_PING_PERIOD

local mock_device = H.new_device()
local speaker = H.new_speaker(H.IP)
local upgrade

test.set_test_init_function(function()
  test.mock_device.add_test_device(mock_device)
  H.seed(mock_device)
  speaker:activate()
  upgrade = H.expect_upgrade(speaker)
end)

local function online() return test.mock_devices_api.__is_device_online(mock_device.id) == true end
local function offline() return test.mock_devices_api.__is_device_online(mock_device.id) == false end

--- Accept the driver's WebSocket connection and wait for the device to come online.
local function connect()
  H.accept_upgrade(upgrade, 5)
  test.wait_until(online, { within = 5, message = "the device online" })
end

local function sent_messages() return H.client_messages(speaker.ws:connection()) end

test.register_coroutine_test(
  "state updates from the speaker become capability events",
  function()
    connect()
    test.socket.capability:__set_channel_ordering("relaxed") -- the order the handler emits in doesn't matter
    local function expect(event) test.socket.capability:__expect_send(mock_device:generate_test_message("main", event)) end
    expect(capabilities.switch.switch.on())
    expect(capabilities.audioVolume.volume(30))
    expect(capabilities.audioMute.mute.muted())
    expect(capabilities.mediaPlayback.playbackStatus.playing())
    speaker.ws:connection():queue_bytes(H.text_frame({ switch = "on", audioVolume = 30, audioMute = true,
      mediaPlayback = "play" }))
    test.wait_for_events()
  end,
  { min_api_version = 23 }
)

test.register_coroutine_test(
  "the driver refreshes on connecting, then sends commands with the credential token",
  function()
    connect()
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = "switch", component = "main", command = "on", args = {} } })
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = "audioVolume", component = "main", command = "setVolume", args = { 42 } } })
    test.wait_until(function() return #sent_messages() >= 3 end, { within = 5, message = "refresh and two commands sent" })

    local refresh, switch_on, set_volume = table.unpack(sent_messages())
    assert(refresh.message.command == "refresh" and refresh.message.capability == "refresh",
      "the first message is the refresh sent on connecting")
    assert(switch_on.message.capability == "switch" and switch_on.message.command == "on", "switch on")
    assert(switch_on.credential == H.TOKEN, "commands carry the device's credential token")
    assert(set_volume.message.capability == "audioVolume" and set_volume.message.command == "setVolume"
      and set_volume.message.arg.volume == 42, "setVolume carries its argument")
  end,
  { min_api_version = 23 }
)

test.register_coroutine_test(
  "a speaker that stops answering the keepalive is reported offline and reconnected",
  function()
    connect()
    local second_upgrade = H.expect_upgrade(speaker)
    test.mock_devices_api.__clear_device_status_history()

    test.let_time_pass(WS_IDLE_PING_PERIOD - 1)
    assert(online(), "the device went offline before the keepalive was due")
    test.wait_until(offline, { within = 120, message = "the device offline after a missed keepalive reply" })
    assert(H.count_pings(speaker.ws:connection(1)) >= 1, "the driver sent a keepalive ping")

    H.accept_upgrade(second_upgrade, 60)
    test.wait_until(online, { within = 60, message = "the device back online after reconnecting" })
    assert(speaker.ws:connection_count() == 2, "expected one reconnection")
    assert(test.mock_devices_api.__count_device_status_calls(mock_device.id, false) == 1, "offline exactly once")
  end,
  { min_api_version = 23 }
)

test.register_coroutine_test(
  "when the speaker closes the WebSocket the driver reconnects and refreshes",
  function()
    connect()
    local second_upgrade = H.expect_upgrade(speaker)
    speaker.ws:connection():close_connection()
    H.accept_upgrade(second_upgrade, 30)
    test.wait_until(online, { within = 5 })

    assert(speaker.ws:connection_count() == 2, "expected one reconnection")
    test.wait_until(function() return #sent_messages() >= 1 end, { within = 5, message = "the refresh after reconnecting" })
    assert(sent_messages()[1].message.command == "refresh", "the driver refreshes after reconnecting")
  end,
  { min_api_version = 23 }
)

test.register_coroutine_test(
  "when the speaker resets the connection the driver reconnects and refreshes",
  function()
    connect()
    local second_upgrade = H.expect_upgrade(speaker)
    test.mock_devices_api.__clear_device_status_history()
    speaker.ws:connection():reset_connection()
    H.accept_upgrade(second_upgrade, 60)
    test.wait_until(online, { within = 5, message = "the device online after reconnecting" })

    assert(speaker.ws:connection_count() == 2, "expected one reconnection")
    test.wait_until(function() return #sent_messages() >= 1 end, { within = 5, message = "the refresh after reconnecting" })
    assert(sent_messages()[1].message.command == "refresh", "the driver refreshes after reconnecting")
  end,
  { min_api_version = 23 }
)

test.register_coroutine_test(
  "a speaker that refuses reconnects while it restarts is reported offline until it accepts one",
  function()
    connect()
    local second_upgrade = H.expect_upgrade(speaker)
    test.mock_devices_api.__clear_device_status_history()
    speaker.ws_scenario:fail_connects(2, "connection refused")
    speaker.ws:connection():close_connection()

    test.wait_until(offline, { within = 30, message = "the device offline while connects are refused" })
    H.accept_upgrade(second_upgrade, 60)
    test.wait_until(online, { within = 5, message = "the device online once a connection is accepted" })
    assert(speaker.ws_scenario:failed_connect_count() == 2, "expected the driver to have been refused twice")
  end,
  { min_api_version = 23 }
)

-- DRIVER BUG, worked around here: the driver "spawns" tasks by calling them, as in
-- `cosock.spawn(self:listener(), ...)` (HLWebsocket:start) and `cosock.spawn(self:try_reconnect(), ...)`
-- (the listener), so spawn gets what they return instead of a function, and raises. A WebSocket the
-- driver closed itself (for a speaker another hub owns) makes its listener return nil to the spawn in
-- `start`; one the speaker closed makes the listener pass a refused reconnect's `false` to the spawn
-- in the listener. Spawn nothing for a non-function so the reconnect decision itself can be checked.
-- Remove once hl_websocket.lua passes the functions.
local function spawn_only_functions()
  local cosock = require "cosock"
  local spawn = cosock.spawn
  cosock.spawn = function(fn, name)
    if type(fn) == "function" then return spawn(fn, name) end
  end
  return function() cosock.spawn = spawn end
end

-- Pairing with another hub gave the speaker a new token, which it reports as the active one from then on.
local function another_hub_owns_the_speaker()
  http.expect_request(speaker.api, "GET", "/api/getData", {
    query = H.get_data_query("settings:/smartthings/userToken"), body = H.string_value("tok-other-hub"),
    reusable = true, prepend = true,
  })
end

local another_hub_cases = {
  {
    name = "a speaker that was paired with another hub is set offline and left alone",
    trigger = function()
      -- it tells the open WebSockets about the new token
      speaker.ws:connection():queue_bytes(H.text_frame({ credential = "tok-other-hub" }))
    end,
  },
  {
    name = "a speaker that closes the WebSocket after being paired with another hub is not reconnected to",
    trigger = function() speaker.ws:connection():close_connection() end,
  },
}
for _, case in ipairs(another_hub_cases) do
  test.register_coroutine_test(
    case.name,
    function()
      local restore_spawn = spawn_only_functions()
      connect()
      another_hub_owns_the_speaker()
      test.mock_devices_api.__clear_device_status_history()
      case.trigger()

      test.wait_until(offline, { within = 5, message = "the device offline" })
      test.let_time_pass(120)
      assert(offline(), "the device came back online")
      assert(speaker.ws:connection_count() == 1, "the driver reconnected to a speaker another hub owns")
      restore_spawn()
    end,
    { min_api_version = 23 }
  )
end

-- Every command the driver passes through to the speaker as it is: `args` is what the hub sends,
-- `arg` what the speaker should receive them as.
local command_cases = {
  { capability = "switch", command = "on" },
  { capability = "switch", command = "off" },
  { capability = "audioMute", command = "mute" },
  { capability = "audioMute", command = "unmute" },
  { capability = "audioMute", command = "setMute", args = { "muted" }, arg = { state = "muted" } },
  { capability = "audioVolume", command = "volumeUp" },
  { capability = "audioVolume", command = "volumeDown" },
  { capability = "mediaInputSource", command = "setInputSource", args = { "wifi" }, arg = { mode = "wifi" } },
  { capability = "mediaPlayback", command = "play" },
  { capability = "mediaPlayback", command = "pause" },
  { capability = "mediaPlayback", command = "stop" },
  { capability = "mediaTrackControl", command = "nextTrack" },
  { capability = "mediaTrackControl", command = "previousTrack" },
  { capability = "audioNotification", command = "playTrack",
    args = { "http://hub.local/chime.mp3", 40 }, arg = { uri = "http://hub.local/chime.mp3", level = 40 } },
  { capability = "audioNotification", command = "playTrackAndResume",
    args = { "http://hub.local/chime.mp3", 40 }, arg = { uri = "http://hub.local/chime.mp3", level = 40 } },
  { capability = "audioNotification", command = "playTrackAndRestore",
    args = { "http://hub.local/chime.mp3", 40 }, arg = { uri = "http://hub.local/chime.mp3", level = 40 } },
}
for _, case in ipairs(command_cases) do
  test.register_coroutine_test(
    string.format("the %s %s command is sent to the speaker with the credential token", case.capability, case.command),
    function()
      connect()
      test.socket.capability:__queue_receive({ mock_device.id,
        { capability = case.capability, component = "main", command = case.command, args = case.args or {} } })
      test.wait_until(function() return #sent_messages() >= 2 end, { within = 5, message = "refresh and the command sent" })

      local sent = sent_messages()[2]
      assert(sent.message.capability == case.capability and sent.message.command == case.command,
        "the frame names the capability and command")
      assert(sent.credential == H.TOKEN, "the frame carries the device's credential token")
      for name, value in pairs(case.arg or {}) do
        assert(sent.message.arg[name] == value, "the command's " .. name .. " argument")
      end
    end,
    { min_api_version = 23 }
  )
end

-- What the speaker reports besides the basic state test above: each of these is a handler of its own.
local push_cases = {
  {
    name = "a stopped player clears the track data",
    message = { mediaPlayback = "stop" },
    events = {
      capabilities.mediaPlayback.playbackStatus.stopped(),
      capabilities.audioTrackData.audioTrackData({ title = "" }),
      capabilities.audioTrackData.totalTime(0),
    },
  },
  {
    name = "the track that is playing",
    message = { audioTrackData = {
      audioTrackData = { title = "So What", artist = "Miles Davis", album = "Kind of Blue" }, totalTime = 562,
    } },
    events = {
      capabilities.audioTrackData.audioTrackData({ title = "So What", artist = "Miles Davis", album = "Kind of Blue" }),
      capabilities.audioTrackData.totalTime(562),
    },
  },
  {
    name = "the speaker's media presets",
    message = { mediaPresets = { { id = "1", name = "Jazz" }, { id = "2", name = "Rock" } } },
    events = { capabilities.mediaPresets.presets({ { id = "1", name = "Jazz" }, { id = "2", name = "Rock" } }) },
  },
  {
    name = "the speaker's supported input sources",
    message = { supportedInputSources = { "wifi", "bluetooth" } },
    events = { capabilities.mediaInputSource.supportedInputSources({ "wifi", "bluetooth" }) },
  },
  {
    name = "the selected input source",
    message = { mediaInputSource = "bluetooth" },
    events = { capabilities.mediaInputSource.inputSource.bluetooth() },
  },
}
for _, case in ipairs(push_cases) do
  test.register_coroutine_test(
    "the speaker reports: " .. case.name,
    function()
      connect()
      test.socket.capability:__set_channel_ordering("relaxed") -- the order the handler emits in doesn't matter
      for _, event in ipairs(case.events) do
        test.socket.capability:__expect_send(mock_device:generate_test_message("main", event))
      end
      speaker.ws:connection():queue_bytes(H.text_frame(case.message))
      test.wait_for_events()
    end,
    { min_api_version = 23 }
  )
end

test.register_coroutine_test(
  "a media preset is played by its id, however the command names it",
  function()
    connect()
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.mediaPresets.presets({ { id = "1", name = "Jazz" } })))
    speaker.ws:connection():queue_bytes(H.text_frame({ mediaPresets = { { id = "1", name = "Jazz" } } }))
    test.wait_for_events()

    -- a routine may name the preset loosely
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = "mediaPresets", component = "main", command = "playPreset", args = { "Preset jazz" } } })
    test.wait_until(function() return #sent_messages() >= 2 end, { within = 5, message = "the preset played" })
    local play = sent_messages()[2]
    assert(play.message.command == "playPreset" and play.message.arg.presetId == "1",
      "the speaker is asked to play the preset by its id")

    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = "mediaPresets", component = "main", command = "playPreset", args = { "nonexistent" } } })
    test.wait_for_events()
    test.let_time_pass(1)
    assert(#sent_messages() == 2, "a preset the speaker doesn't have was sent to it")
  end,
  { min_api_version = 23 }
)

test.register_coroutine_test(
  "renaming the device renames the speaker",
  function()
    connect()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({ label = "Den" }))
    test.wait_until(function() return http.count_requests(speaker.api, "GET", "/api/setData") >= 1 end,
      { within = 5, message = "the rename request" })

    local request = http.sent_requests(speaker.api)[1]
    assert(request.query:find("deviceName", 1, true) and request.query:find("Den", 1, true),
      "the speaker was asked to set its name to the new label, got " .. request.query)
  end,
  { min_api_version = 23 }
)

test.register_coroutine_test(
  "removing the device closes its WebSocket",
  function()
    connect()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "removed" })
    test.wait_until(function() return H.count_frames(speaker.ws:connection(), 0x8) == 1 end,
      { within = 5, message = "a close frame" })
  end,
  { min_api_version = 23 }
)

test.run_registered_tests()
