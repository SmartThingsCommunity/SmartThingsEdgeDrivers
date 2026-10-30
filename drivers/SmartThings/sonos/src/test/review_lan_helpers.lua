-- Framework-evaluation helpers for the Sonos review tests (not a driver test itself).
--
-- Everything WebSocket-specific in here (frame encode/decode, upgrade response, the framer/parser
-- that lets connection_scenario carry a WebSocket connection) is NOT provided by the framework.
local test = require "integration_test"
local json = require "st.json"
local base64 = require "base64"
local sha1 = require "sha1"

-- LAN driver tests need test coroutine priority and (for current hubs) batched capability receive.
test.set_test_coroutine_priority(true)
test.set_capability_batch_receive(true)

-- The driver loads its API keys from an `app_key` module that is not checked in. Supply one so the
-- driver's own code paths run; this does not modify driver source.
package.preload["app_key"] = function()
  return { s1_key = "test-s1-key", oauth_key = "test-oauth-key" }
end

-- stus.softwareGeneration is a driver-package capability (sonos/capabilities/softwareGeneration.yaml).
test.add_package_capability("softwareGeneration.yaml")

local connection_scenario = require "integration_test.connection_scenario"
local http = require "integration_test.connection_scenario_http"

local M = {}

M.PLAYER_IP = "192.168.1.50"
M.PLAYER_PORT = 1443
M.MAC = "AABBCCDDEEFF"
M.HOUSEHOLD = "Sonos_HH1"
M.PLAYER_ID = "RINCON_AABBCCDDEEFF01400"
M.GROUP_ID = M.PLAYER_ID .. ":1"
M.SEARCH_TERM = "urn:smartspeaker-audio:service:SpeakerGroup:1"

--#region WebSocket frames (server side builds unmasked frames, decodes the driver's masked ones)

--- Build an unmasked server -> client frame.
function M.ws_frame(opcode, payload, fin)
  payload = payload or ""
  local b1 = (fin == false and 0 or 0x80) | opcode
  local len = #payload
  local header
  if len < 126 then
    header = string.char(b1, len)
  elseif len < 65536 then
    header = string.char(b1, 126, len >> 8, len & 0xff)
  else
    header = string.char(b1, 127, 0, 0, 0, 0, (len >> 24) & 0xff, (len >> 16) & 0xff, (len >> 8) & 0xff, len & 0xff)
  end
  return header .. payload
end

--- A text frame carrying a Sonos `[header, body]` JSON message.
function M.ws_json(header, body)
  return M.ws_frame(0x1, json.encode({ header, body or {} }))
end

function M.ws_close(code, reason)
  code = code or 1000
  return M.ws_frame(0x8, string.char(code >> 8, code & 0xff) .. (reason or ""))
end

--- Decode as many complete client frames as `bytes` holds.
--- @return table[] frames `{ opcode, payload, masked }`
--- @return number consumed
function M.decode_client_frames(bytes)
  local frames, pos = {}, 1
  while true do
    if #bytes - pos + 1 < 2 then break end
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
      local out = {}
      for i = 1, #payload do
        out[i] = string.char(payload:byte(i) ~ mask[((i - 1) % 4) + 1])
      end
      payload = table.concat(out)
    end
    table.insert(frames, { opcode = opcode, payload = payload, masked = masked })
    pos = p + len
  end
  return frames, pos - 1
end

local OPCODE_NAMES = { [0x0] = "cont", [0x1] = "text", [0x2] = "binary", [0x8] = "close", [0x9] = "ping", [0xA] = "pong" }

--#endregion

--#region connection_scenario glue for a WebSocket connection

--- Framer: HTTP until the upgrade request is seen, then WebSocket frames. connection_scenario
--- hands a framer only the bytes it hasn't consumed yet and keeps no per-connection state for it,
--- so this sniffs the first bytes ("GET " = HTTP). The "request" string it returns for a frame is
--- a *decoded* rendering ("WS text <payload>") so patterns/predicates can see through the masking.
local function ws_framer(bytes)
  if bytes:match("^%s*%u+ /") then
    return http.frame_requests(bytes)
  end
  local frames, consumed = M.decode_client_frames(bytes)
  local requests = {}
  for _, f in ipairs(frames) do
    table.insert(requests, string.format("WS %s %s", OPCODE_NAMES[f.opcode] or f.opcode, f.payload))
  end
  return requests, consumed
end

local function ws_parser(request)
  if request:match("^WS ") then
    local kind, payload = request:match("^WS (%S+) (.*)$")
    local info = { ws_kind = kind, ws_payload = payload }
    if kind == "text" then
      local ok, decoded = pcall(json.decode, payload)
      if ok then
        info.ws_json = decoded
        info.header, info.body = decoded[1], decoded[2]
      end
    end
    return info
  end
  return http.parse_request(request)
end

local GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

--- 101 Switching Protocols response for an upgrade request (computes Sec-WebSocket-Accept).
function M.upgrade_response(req)
  local key = req.headers["sec-websocket-key"]
  assert(key, "upgrade request had no Sec-WebSocket-Key")
  local accept = base64.encode(sha1.binary(key .. GUID))
  return table.concat({
    "HTTP/1.1 101 Switching Protocols",
    "Upgrade: websocket",
    "Connection: Upgrade",
    "Sec-WebSocket-Accept: " .. accept,
    "Sec-WebSocket-Protocol: v1.api.smartspeaker.audio",
    "", "",
  }, "\r\n")
end

--- Expect Sonos message(s) from the driver on a websocket logical connection.
--- @param conn LogicalConnection
--- @param spec table `{ namespace=, command=, check=function(header, body) -> ok, reason }` plus
---   any `expect` option (reusable, times, optional, ...)
function M.expect_ws_message(conn, spec)
  local s = {}
  for k, v in pairs(spec) do s[k] = v end
  local ns, cmd, check = s.namespace, s.command, s.check
  s.namespace, s.command, s.check = nil, nil, nil
  s.request = {
    pattern = "^WS text ",
    description = string.format("ws %s.%s", tostring(ns), tostring(cmd)),
    predicate = function(req)
      local payload = req:match("^WS text (.*)$")
      local ok, decoded = pcall(json.decode, payload)
      if not ok or type(decoded) ~= "table" then return false, "not JSON" end
      local header, body = decoded[1], decoded[2]
      if ns and header.namespace ~= ns then return false, "namespace " .. tostring(header.namespace) end
      if cmd and header.command ~= cmd then return false, "command " .. tostring(header.command) end
      if check then return check(header, body) end
      return true
    end,
  }
  s.description = s.request.description
  s.responses = s.responses or {}
  return conn:expect(s)
end

--- All Sonos messages the driver sent on a websocket logical connection so far, decoded.
function M.sent_ws_messages(conn)
  local out = {}
  for i = 1, conn:connection_count() do
    local sent = conn:connection(i):sent()
    local http_end = sent:find("\r\n\r\n", 1, true)
    local frames = M.decode_client_frames(sent:sub((http_end or #sent) + 4))
    for _, f in ipairs(frames) do
      if f.opcode == 0x1 then
        local d = json.decode(f.payload)
        table.insert(out, { header = d[1], body = d[2] })
      end
    end
  end
  return out
end

--#endregion

--#region Sonos payloads

function M.ssdp_reply(opts)
  opts = opts or {}
  local ip = opts.ip or M.PLAYER_IP
  return table.concat({
    "HTTP/1.1 200 OK",
    "CACHE-CONTROL: max-age = 1800",
    "EXT:",
    string.format("LOCATION: http://%s:1400/xml/device_description.xml", ip),
    "SERVER: Linux UPnP/1.0 Sonos/70.3-88200 (ZPS9)",
    "ST: " .. M.SEARCH_TERM,
    string.format("USN: uuid:%s::%s", opts.player_id or M.PLAYER_ID, M.SEARCH_TERM),
    "HOUSEHOLD.SMARTSPEAKER.AUDIO: " .. (opts.household or M.HOUSEHOLD),
    string.format('GROUPINFO.SMARTSPEAKER.AUDIO: gc=1; gid=%s; gname="Kitchen"', opts.group_id or M.GROUP_ID),
    string.format("WEBSOCK.SMARTSPEAKER.AUDIO: wss://%s:%d/websocket/api", ip, M.PLAYER_PORT),
    "", "",
  }, "\r\n")
end

function M.player_info(opts)
  opts = opts or {}
  local ip = opts.ip or M.PLAYER_IP
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

function M.groups_response(opts)
  opts = opts or {}
  local ip = opts.ip or M.PLAYER_IP
  return {
    _objectType = "groups",
    groups = {
      { id = M.GROUP_ID, name = "Kitchen", coordinatorId = M.PLAYER_ID, playbackState = "PLAYBACK_STATE_IDLE",
        playerIds = { M.PLAYER_ID } },
    },
    players = {
      { id = M.PLAYER_ID, name = "Kitchen", websocketUrl = string.format("wss://%s:%d/websocket/api", ip, M.PLAYER_PORT),
        devices = { { id = M.PLAYER_ID } } },
    },
  }
end

--#endregion

--- Build the scenario for the player's address: a "rest" connection (one-shot HTTP GETs under
--- /api/) and a "ws" connection (the upgrade to /websocket/api, then WebSocket frames).
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

--- Register the persistent expectations: REST answers, the upgrade, and the subscribe messages.
function M.register_standard_expectations(rest, ws, opts)
  opts = opts or {}
  http.expect_request(rest, "GET", "/api/v1/players/local/info", {
    body = M.player_info(opts), reusable = true,
  })
  http.expect_request(rest, "GET", "/api/v1/households/" .. M.HOUSEHOLD .. "/groups", {
    body = M.groups_response(opts), reusable = true,
  })
  ws:expect({
    request = { pattern = "^GET /websocket/api" },
    description = "websocket upgrade",
    responses = { { generator = M.upgrade_response } },
    reusable = true,
  })
  -- The driver answers a server Close frame (and closes on shutdown) with its own Close frame.
  ws:expect({ request = { pattern = "^WS close" }, description = "ws close frame", responses = {}, reusable = true })
  for _, ns in ipairs({ "groups", "playerVolume", "audioClip", "groupVolume", "playback", "favorites", "playbackMetadata" }) do
    M.expect_ws_message(ws, { namespace = ns, command = "subscribe", reusable = true })
  end
end

--- The sonos-player profile, built by hand: `t_utils.get_profile_definition("sonos-player.yml")`
--- fails to parse this driver's profile because the test framework's yaml parser can't read the
--- escaped quotes in the `queueAction` preference title.
function M.mock_device(overrides)
  local caps = {}
  for _, id in ipairs({ "mediaPlayback", "mediaGroup", "mediaPresets", "mediaTrackControl", "audioMute",
    "audioNotification", "audioTrackData", "audioVolume", "stus.softwareGeneration", "refresh" }) do
    table.insert(caps, { id = id, version = 1 })
  end
  local d = {
    profile = { components = { main = { id = "main", capabilities = caps } }, preferences = {} },
    device_network_id = M.MAC,
    label = "Kitchen",
  }
  for k, v in pairs(overrides or {}) do d[k] = v end
  return test.mock_device.build_test_lan_device(d)
end

--- The Sonos driver keeps process-wide state in module locals (the websocket router's socket table
--- and its `cosock.spawn`ed task are created when the module loads; SonosState is a singleton).
--- The framework resets cosock between tests but not `package.loaded`, so from the second test in a
--- process on, the router's task is dead and its socket table is stale. Work around it by
--- unloading every module that comes from the driver's own source tree before each test.
function M.unload_driver_modules()
  local names = {}
  for name in pairs(package.loaded) do
    if not name:match("^test%.") and not name:match("^cosock") and name ~= "init" then
      local found = package.searchpath(name, package.path)
      if found and found:sub(1, 2) == "./" then table.insert(names, name) end
    end
  end
  for _, name in ipairs(names) do package.loaded[name] = nil end
end

--- Everything a test file needs: scenario + connections, the mock device, and the SSDP peer.
--- Call `ctx.init` from set_test_init_function and `ctx.bring_up()` from a coroutine test body.
function M.new_context(opts)
  local capabilities = require "st.capabilities"
  local mock_lan_socket = require "integration_test.mock_lan_socket"
  local mock_devices_api = require "integration_test.mock_devices_api"
  opts = opts or {}
  local ctx = { opts = opts }
  ctx.scenario, ctx.rest, ctx.ws = M.create_scenario(opts.ip)
  M.register_standard_expectations(ctx.rest, ctx.ws, opts)
  ctx.device = M.mock_device()

  function ctx.event(cap_event)
    test.socket.capability:__expect_send(ctx.device:generate_test_message("main", cap_event))
  end

  function ctx.init()
    M.unload_driver_modules()
    ctx.scenario:activate()
    ctx.ssdp = mock_lan_socket.udp_peer("239.255.255.250", 1900)
    if opts.rescan_timer then
      -- cosock.timer is mocked and never fires unless the test queues a timer for the driver's
      -- next create_interval(); this is the persistent SSDP task's 600 s rescan.
      test.timer.__create_and_queue_test_time_advance_timer(600, "interval", 1)
    end
    test.socket.capability:__set_channel_ordering("relaxed")
    if not opts.no_device then
      test.mock_device.add_test_device(ctx.device)
      ctx.event(capabilities.mediaPlayback.supportedPlaybackCommands({ "play", "pause", "stop" }))
      ctx.event(capabilities.mediaTrackControl.supportedTrackControlCommands({ "nextTrack", "previousTrack" }))
    end
  end

  function ctx.is_online()
    return mock_devices_api.__is_device_online(ctx.device.id)
  end

  --- SSDP search -> reply -> REST info/groups -> websocket upgrade -> subscribes -> online.
  function ctx.bring_up()
    ctx.event(capabilities["stus.softwareGeneration"].generation("2"))
    ctx.event(capabilities.mediaGroup.groupRole("ungrouped"))
    ctx.event(capabilities.mediaGroup.groupPrimaryDeviceId(M.PLAYER_ID))
    test.wait_until(function() return #ctx.ssdp:sent() > 0 end, { message = "the driver's M-SEARCH" })
    ctx.ssdp:reply(M.ssdp_reply(), { from_host = M.PLAYER_IP, from_port = 1900 })
    test.wait_until(ctx.is_online, { message = "the device online", max_turns = 200 })
    test.wait_for_events()
  end

  return ctx
end

return M
