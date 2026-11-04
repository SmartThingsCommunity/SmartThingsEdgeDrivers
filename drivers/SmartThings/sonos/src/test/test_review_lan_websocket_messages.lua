-- Use case 1: protocol message <-> capability over the Sonos WebSocket.
local helpers = require "test.review_lan_helpers"
local test = require "integration_test"
local capabilities = require "st.capabilities"

local ctx = helpers.new_context()
test.set_test_init_function(ctx.init)

local function header(type_, extra)
  local h = { namespace = type_, type = type_, householdId = helpers.HOUSEHOLD, groupId = helpers.GROUP_ID,
    playerId = helpers.PLAYER_ID }
  for k, v in pairs(extra or {}) do h[k] = v end
  return h
end

test.register_coroutine_test("playbackStatus push emits mediaPlayback.playbackStatus", function()
  ctx.bring_up()
  ctx.event(capabilities.mediaPlayback.playbackStatus.playing())
  ctx.ws:queue_bytes(helpers.ws_json(header("playbackStatus"), { playbackState = "PLAYBACK_STATE_PLAYING" }))
  test.wait_for_events()
  ctx.event(capabilities.mediaPlayback.playbackStatus.paused())
  ctx.ws:queue_bytes(helpers.ws_json(header("playbackStatus"), { playbackState = "PLAYBACK_STATE_PAUSED" }))
  test.wait_for_events()
end)

test.register_coroutine_test("playerVolume push emits volume and mute", function()
  ctx.bring_up()
  ctx.event(capabilities.audioVolume.volume(35))
  ctx.event(capabilities.audioMute.mute.unmuted())
  ctx.ws:queue_bytes(helpers.ws_json(header("playerVolume"), { volume = 35, muted = false }))
  test.wait_for_events()
end)

test.register_coroutine_test("groupVolume push emits mediaGroup events (masked/fragmented delivery)", function()
  ctx.bring_up()
  ctx.event(capabilities.mediaGroup.groupVolume(12))
  ctx.event(capabilities.mediaGroup.groupMute.muted())
  -- Deliver one frame in two TCP chunks to check the driver's frame reassembly.
  local frame = helpers.ws_json(header("groupVolume"), { volume = 12, muted = true })
  ctx.ws:queue_bytes(frame:sub(1, 10))
  test.wait_for_events()
  ctx.ws:queue_bytes(frame:sub(11))
  test.wait_for_events()
end)

test.register_coroutine_test("setVolume command sends playerVolume.setVolume over the websocket", function()
  ctx.bring_up()
  helpers.expect_ws_message(ctx.ws, {
    namespace = "playerVolume", command = "setVolume",
    check = function(h, b)
      if h.playerId ~= helpers.PLAYER_ID then return false, "playerId " .. tostring(h.playerId) end
      if h.householdId ~= helpers.HOUSEHOLD then return false, "householdId" end
      return b.volume == 25, "volume " .. tostring(b.volume)
    end,
  })
  test.socket.capability:__queue_receive({ ctx.device.id,
    { capability = "audioVolume", command = "setVolume", args = { 25 }, component = "main" } })
  test.wait_for_events()
end)

test.register_coroutine_test("play command goes to the group (playback.play)", function()
  ctx.bring_up()
  helpers.expect_ws_message(ctx.ws, {
    namespace = "playback", command = "play",
    check = function(h) return h.groupId == helpers.GROUP_ID, "groupId " .. tostring(h.groupId) end,
  })
  test.socket.capability:__queue_receive({ ctx.device.id,
    { capability = "mediaPlayback", command = "play", args = {}, component = "main" } })
  test.wait_for_events()
end)

test.register_coroutine_test("the upgrade request, TLS use and masked subscribe frames", function()
  ctx.bring_up()
  local sent = ctx.ws:connection():sent()
  assert(sent:match("^GET /websocket/api HTTP/1.1"), "upgrade request line")
  assert(sent:lower():find("upgrade: websocket", 1, true), "upgrade header")
  assert(sent:lower():find("x-sonos-api-key: test-", 1, true), "api key header")
  assert(ctx.ws:connection():tls() and ctx.ws:connection():tls().handshaken, "TLS handshake")
  local frames = helpers.decode_client_frames(sent:sub(sent:find("\r\n\r\n", 1, true) + 4))
  assert(#frames == 7, "expected 7 subscribe frames, got " .. #frames)
  for _, f in ipairs(frames) do assert(f.masked, "client frame must be masked") end
  local namespaces = {}
  for _, m in ipairs(helpers.sent_ws_messages(ctx.ws)) do namespaces[m.header.namespace] = m.header.command end
  assert(namespaces.groups == "subscribe" and namespaces.playback == "subscribe")
end)

test.run_registered_tests()
