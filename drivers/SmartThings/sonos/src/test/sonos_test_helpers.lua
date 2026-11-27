-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- Shared fixtures for the Sonos driver's tests (not a test file itself).
---
--- A Sonos player is reached three ways, and the fixture models each one against the mock LAN
--- sockets: the driver multicasts SSDP M-SEARCH queries, and the player answers from its own
--- address (`fixture.ssdp`, a mock UDP peer); the driver reads the player's info and groups over
--- one-shot HTTPS requests (`fixture.rest`); and it then holds a WebSocket open to the player
--- (`fixture.ws`), subscribes to the player's namespaces on it, and exchanges Sonos
--- `[header, body]` JSON messages. The two TCP connections share one `connection_scenario` for
--- the player's address.
---
--- `connection_scenario` has no WebSocket support, so this module supplies what a WebSocket
--- connection needs: the frames (`ws_json`, `ws_close`, `decode_client_frames`), the upgrade
--- response, and a framer and parser that carry the connection from its HTTP upgrade request
--- onto WebSocket frames. `fixture.bring_up()` takes a known player from the first search to an
--- online device.

local test = require "integration_test"
local t_utils = require "integration_test.utils"
local json = require "st.json"
local base64 = require "base64"
local sha1 = require "sha1"

-- LAN driver tests need test coroutine priority and, as hubs always provide it, batched
-- capability receive.
test.set_test_coroutine_priority(true)
test.set_capability_batch_receive(true)

-- The driver loads its API keys from an `app_key` module that isn't checked in, and without keys
-- it can't authenticate a player at all; supply a stand-in.
package.preload["app_key"] = function()
  return { s1_key = "test-s1-key", oauth_key = "test-oauth-key" }
end

-- stus.softwareGeneration is a capability of the driver package, not of the platform.
test.add_package_capability("softwareGeneration.yaml")

local connection_scenario = require "integration_test.connection_scenario"
local http = require "integration_test.connection_scenario_http"
local mock_lan_socket = test.mock_lan_socket

local M = {}

M.PLAYER_IP = "192.168.1.50"
M.PLAYER_PORT = 1443
M.MAC = "AABBCCDDEEFF"
M.HOUSEHOLD = "Sonos_HH1"
M.PLAYER_ID = "RINCON_AABBCCDDEEFF01400"
M.GROUP_ID = M.PLAYER_ID .. ":1"
M.SEARCH_TERM = "urn:smartspeaker-audio:service:SpeakerGroup:1"

-- What the driver subscribes to on connecting: the player's own namespaces, and those of its
-- group's coordinator.
M.PLAYER_SUBSCRIPTIONS = { "groups", "playerVolume", "audioClip" }
M.GROUP_SUBSCRIPTIONS = { "groupVolume", "playback", "favorites", "playbackMetadata" }

--#region WebSocket frames

--- Build an unmasked server -> client frame.
function M.ws_frame(opcode, payload)
  payload = payload or ""
  local len = #payload
  local header
  if len < 126 then
    header = string.char(0x80 | opcode, len)
  elseif len < 65536 then
    header = string.char(0x80 | opcode, 126, len >> 8, len & 0xff)
  else
    header = string.char(0x80 | opcode, 127, 0, 0, 0, 0,
      (len >> 24) & 0xff, (len >> 16) & 0xff, (len >> 8) & 0xff, len & 0xff)
  end
  return header .. payload
end

--- A text frame carrying a Sonos `[header, body]` JSON message.
function M.ws_json(header, body)
  return M.ws_frame(0x1, json.encode({ header, body or {} }))
end

function M.ws_close(code, reason)
  return M.ws_frame(0x8, string.char(code >> 8, code & 0xff) .. (reason or ""))
end

--- Decode as many complete client frames as `bytes` holds (a client masks its frames).
--- @return table[] frames `{ opcode, payload, masked }`
--- @return number consumed
function M.decode_client_frames(bytes)
  local frames, pos = {}, 1
  while #bytes - pos + 1 >= 2 do
    local b1, b2 = bytes:byte(pos, pos + 1)
    local opcode, masked, len = b1 & 0x0f, (b2 & 0x80) ~= 0, b2 & 0x7f
    local p = pos + 2
    if len == 126 then
      if #bytes - p + 1 < 2 then break end
      local hi, lo = bytes:byte(p, p + 1)
      len, p = (hi << 8) | lo, p + 2
    elseif len == 127 then
      if #bytes - p + 1 < 8 then break end
      len = 0
      for i = 0, 7 do len = (len << 8) | bytes:byte(p + i) end
      p = p + 8
    end
    local mask
    if masked then
      if #bytes - p + 1 < 4 then break end
      mask = { bytes:byte(p, p + 3) }
      p = p + 4
    end
    if #bytes - p + 1 < len then break end
    local payload = bytes:sub(p, p + len - 1)
    if masked then
      local unmasked = {}
      for i = 1, #payload do
        unmasked[i] = string.char(payload:byte(i) ~ mask[((i - 1) % 4) + 1])
      end
      payload = table.concat(unmasked)
    end
    table.insert(frames, { opcode = opcode, payload = payload, masked = masked })
    pos = p + len
  end
  return frames, pos - 1
end

local OPCODE_NAMES = { [0x0] = "cont", [0x1] = "text", [0x2] = "binary", [0x8] = "close", [0x9] = "ping", [0xA] = "pong" }

local WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

--- The 101 Switching Protocols response to the driver's upgrade request.
function M.upgrade_response(req)
  local key = req.headers["sec-websocket-key"]
  assert(key, "the upgrade request had no Sec-WebSocket-Key")
  return table.concat({
    "HTTP/1.1 101 Switching Protocols",
    "Upgrade: websocket",
    "Connection: Upgrade",
    "Sec-WebSocket-Accept: " .. base64.encode(sha1.binary(key .. WS_GUID)),
    "Sec-WebSocket-Protocol: v1.api.smartspeaker.audio",
    "", "",
  }, "\r\n")
end

--#endregion

--#region The websocket connection's framer and parser

--- A connection's first request is its HTTP upgrade request; everything the driver sends after it
--- is WebSocket frames. The framer keeps that in the connection's state, and renders each frame
--- as "WS <kind> <payload>" (unmasked) for expectations to match.
local function ws_framer(bytes, state)
  local requests, consumed = {}, 0
  if not state.upgraded then
    local upgrade = http.frame_requests(bytes)[1]
    if not upgrade then return requests, 0 end
    state.upgraded = true
    requests[1], consumed = upgrade, #upgrade
  end
  local frames, used = M.decode_client_frames(bytes:sub(consumed + 1))
  for _, frame in ipairs(frames) do
    table.insert(requests, string.format("WS %s %s", OPCODE_NAMES[frame.opcode] or frame.opcode, frame.payload))
  end
  return requests, consumed + used
end

local function ws_parser(request)
  if request:match("^WS ") then return {} end
  return http.parse_request(request)
end

--- Expect a Sonos message from the driver on the websocket connection.
--- @param conn LogicalConnection
--- @param namespace string
--- @param command string
--- @param opts table|nil `header` and `body`: fields the message's header or body must contain
---   (see `http.json_matches`), plus any option of `LogicalConnection:expect` (`reusable`, ...)
function M.expect_ws_message(conn, namespace, command, opts)
  local spec = {}
  for k, v in pairs(opts or {}) do spec[k] = v end
  local want_header, want_body = spec.header, spec.body
  spec.header, spec.body = nil, nil
  spec.description = string.format("websocket %s.%s", namespace, command)
  spec.request = {
    pattern = "^WS text ",
    description = spec.description,
    predicate = function(request)
      local ok, message = pcall(json.decode, request:match("^WS text (.*)$"))
      if not ok or type(message) ~= "table" then return false, "not a Sonos message" end
      local header, body = message[1], message[2]
      if header.namespace ~= namespace then return false, "namespace " .. tostring(header.namespace) end
      if header.command ~= command then return false, "command " .. tostring(header.command) end
      if want_header and not http.json_matches(header, want_header) then return false, "header " .. json.encode(header) end
      if want_body and not http.json_matches(body, want_body) then return false, "body " .. json.encode(body) end
      return true
    end,
  }
  spec.responses = {}
  return conn:expect(spec)
end

--- The WebSocket frames the driver sent on one of the websocket connections.
--- @param conn LogicalConnection
--- @param which number|nil the n-th connection the driver made (default the newest)
--- @return table[] frames `{ opcode, payload, masked }`
function M.sent_ws_frames(conn, which)
  local sent = conn:connection(which):sent()
  local upgrade_end = select(2, sent:find("\r\n\r\n", 1, true))
  return (M.decode_client_frames(sent:sub((upgrade_end or #sent) + 1)))
end

--- The Sonos messages the driver sent on one of the websocket connections, decoded.
--- @return table[] messages `{ header, body }`
function M.sent_ws_messages(conn, which)
  local messages = {}
  for _, frame in ipairs(M.sent_ws_frames(conn, which)) do
    if frame.opcode == 0x1 then
      local message = json.decode(frame.payload)
      table.insert(messages, { header = message[1], body = message[2] })
    end
  end
  return messages
end

--#endregion

--#region Sonos payloads

--- A player's reply to the driver's SSDP search.
--- @param opts table|nil `ip` (the player's address, default PLAYER_IP)
function M.ssdp_reply(opts)
  local ip = (opts and opts.ip) or M.PLAYER_IP
  return table.concat({
    "HTTP/1.1 200 OK",
    "CACHE-CONTROL: max-age = 1800",
    "EXT:",
    string.format("LOCATION: http://%s:1400/xml/device_description.xml", ip),
    "SERVER: Linux UPnP/1.0 Sonos/70.3-88200 (ZPS9)",
    "ST: " .. M.SEARCH_TERM,
    string.format("USN: uuid:%s::%s", M.PLAYER_ID, M.SEARCH_TERM),
    "HOUSEHOLD.SMARTSPEAKER.AUDIO: " .. M.HOUSEHOLD,
    string.format('GROUPINFO.SMARTSPEAKER.AUDIO: gc=1; gid=%s; gname="Kitchen"', M.GROUP_ID),
    string.format("WEBSOCK.SMARTSPEAKER.AUDIO: wss://%s:%d/websocket/api", ip, M.PLAYER_PORT),
    "", "",
  }, "\r\n")
end

--- The body of `GET /api/v1/players/local/info`.
function M.player_info(opts)
  local ip = (opts and opts.ip) or M.PLAYER_IP
  return {
    _objectType = "playerInfo",
    playerId = M.PLAYER_ID,
    groupId = M.GROUP_ID,
    websocketUrl = string.format("wss://%s:%d/websocket/api", ip, M.PLAYER_PORT),
    restUrl = string.format("https://%s:%d/api/v1", ip, M.PLAYER_PORT),
    householdId = M.HOUSEHOLD,
    device = {
      id = M.PLAYER_ID,
      name = "Kitchen",
      model = "sonos-one",
      modelDisplayName = "Sonos One",
      serialNumber = "AA-BB-CC-DD-EE-FF:1",
      swGen = 2,
      primaryDeviceId = M.PLAYER_ID,
    },
  }
end

--- The body of `GET /api/v1/households/<household>/groups`: one group holding the one player.
function M.groups_response(opts)
  local ip = (opts and opts.ip) or M.PLAYER_IP
  return {
    _objectType = "groups",
    groups = {
      { id = M.GROUP_ID, name = "Kitchen", coordinatorId = M.PLAYER_ID, playbackState = "PLAYBACK_STATE_IDLE",
        playerIds = { M.PLAYER_ID } },
    },
    players = {
      { id = M.PLAYER_ID, name = "Kitchen",
        websocketUrl = string.format("wss://%s:%d/websocket/api", ip, M.PLAYER_PORT),
        devices = { { id = M.PLAYER_ID } } },
    },
  }
end

--- The header of a message the player pushes for one of the driver's subscriptions.
function M.push_header(type_, extra)
  local header = { namespace = type_, type = type_, householdId = M.HOUSEHOLD, groupId = M.GROUP_ID,
    playerId = M.PLAYER_ID }
  for k, v in pairs(extra or {}) do header[k] = v end
  return header
end

--#endregion

--- The driver's sonos-player profile.
function M.profile()
  return t_utils.get_profile_definition("sonos-player.yml")
end

--- Build the player's mock LAN device (the one the hub has when the driver starts).
function M.mock_device()
  return test.mock_device.build_test_lan_device({
    profile = M.profile(),
    device_network_id = M.MAC,
    label = "Kitchen",
  })
end

--- Build the scenario for a player's address: a "rest" connection (the one-shot HTTP GETs under
--- /api/) and a "ws" connection (the upgrade to /websocket/api, then WebSocket frames).
--- @return ConnectionScenario scenario
--- @return LogicalConnection rest
--- @return LogicalConnection ws
function M.create_scenario(ip)
  local scenario = connection_scenario.new({ host = ip or M.PLAYER_IP, port = M.PLAYER_PORT })
  local rest = scenario:connection("rest", { matcher = http.matcher("GET", "^/api/") })
  local ws = scenario:connection("ws", {
    matcher = http.matcher("GET", "^/websocket/api"),
    framer = ws_framer,
    parser = ws_parser,
    ordering = "relaxed",
  })
  return scenario, rest, ws
end

--- Register what a healthy player answers on every connection, for every test: its info and
--- groups, the websocket upgrade, and the driver's subscriptions. The driver answers a server
--- Close frame with its own, which needs no reply.
function M.register_player_expectations(rest, ws, opts)
  http.expect_request(rest, "GET", "/api/v1/players/local/info", { body = M.player_info(opts), reusable = true })
  http.expect_request(rest, "GET", "/api/v1/households/" .. M.HOUSEHOLD .. "/groups", {
    body = M.groups_response(opts), reusable = true,
  })
  ws:expect({
    request = { pattern = "^GET /websocket/api" },
    description = "websocket upgrade",
    responses = { { generator = M.upgrade_response } },
    reusable = true,
  })
  ws:expect({ request = { pattern = "^WS close" }, description = "websocket close frame", responses = {}, reusable = true })
  for _, namespace in ipairs(M.PLAYER_SUBSCRIPTIONS) do
    M.expect_ws_message(ws, namespace, "subscribe", { reusable = true })
  end
  for _, namespace in ipairs(M.GROUP_SUBSCRIPTIONS) do
    M.expect_ws_message(ws, namespace, "subscribe", { reusable = true })
  end
end

--- The driver keeps process-wide state in module locals: the websocket router's socket table and
--- the task it `cosock.spawn`s when the module loads, and the SonosState singleton. The framework
--- resets cosock between tests but not `package.loaded`, so from the second test in a process on
--- the router's task would be dead and its socket table stale. Unload every module that comes
--- from the driver's own source tree, so each test's driver loads them afresh.
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

--- Everything a test file needs to run a player: the scenario and its connections (`rest`, `ws`),
--- the mock device (`device`) and the SSDP peer (`ssdp`). Call it at file level, set `test_init`
--- as the file's test_init function (or call it from a test's own), and call `bring_up` from a
--- test body.
---
--- @param opts table|nil
---   - ip: string the player's address (default PLAYER_IP)
function M.new_fixture(opts)
  local capabilities = require "st.capabilities"
  opts = opts or {}
  local fixture = {}
  fixture.scenario, fixture.rest, fixture.ws = M.create_scenario(opts.ip)
  M.register_player_expectations(fixture.rest, fixture.ws, { ip = opts.ip })
  fixture.ssdp = mock_lan_socket.udp_peer("239.255.255.250", 1900)
  fixture.device = M.mock_device()

  --- Expect `device` (default the fixture's) to emit `event`.
  function fixture.expect_event(event, device)
    test.socket.capability:__expect_send((device or fixture.device):generate_test_message("main", event))
  end

  --- What a device emits as soon as the driver initializes it, before it finds the player.
  function fixture.expect_init_events(device)
    fixture.expect_event(capabilities.mediaPlayback.supportedPlaybackCommands({ "play", "pause", "stop" }), device)
    fixture.expect_event(capabilities.mediaTrackControl.supportedTrackControlCommands({ "nextTrack", "previousTrack" }), device)
  end

  --- What a device emits once the driver has read its player's info and groups.
  function fixture.expect_player_events(device)
    fixture.expect_event(capabilities["stus.softwareGeneration"].generation("2"), device)
    fixture.expect_event(capabilities.mediaGroup.groupRole("ungrouped"), device)
    fixture.expect_event(capabilities.mediaGroup.groupPrimaryDeviceId(M.PLAYER_ID), device)
  end

  --- The file's test_init: activate the player's address and, unless `init_opts.no_device` says the
  --- hub has no Sonos device yet (a test of discovery), add the device.
  function fixture.test_init(init_opts)
    unload_driver_modules()
    fixture.scenario:activate()
    -- The driver's threads emit events in no fixed order.
    test.socket.capability:__set_channel_ordering("relaxed")
    if not (init_opts and init_opts.no_device) then
      test.mock_device.add_test_device(fixture.device)
      fixture.expect_init_events()
    end
  end

  --- Whether `device` (default the fixture's) was last marked online.
  function fixture.is_online(device)
    return test.mock_devices_api.__is_device_online((device or fixture.device).id)
  end

  --- The player answers the driver's first SSDP search, and the driver reads its info and groups,
  --- opens and subscribes on its websocket, and marks the device online.
  function fixture.bring_up()
    fixture.expect_player_events()
    test.wait_until(function() return #fixture.ssdp:sent() > 0 end, { within = 10, message = "the driver's M-SEARCH" })
    fixture.ssdp:reply(M.ssdp_reply(opts), { from_host = opts.ip or M.PLAYER_IP })
    test.wait_until(fixture.is_online, { within = 30, message = "the device online" })
    test.wait_for_events()
  end

  return fixture
end

return M
