-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local t_utils = require "integration_test.utils"
local connection_scenario = require "integration_test.connection_scenario"
local http = require "integration_test.connection_scenario_http"
local key_lib = require "lustre.handshake.key"
local json = require "st.json"

-- File-level test modes for every Harman Luxury test file, which all require this module before the
-- driver loads: LAN driver tests run with test coroutine priority, and the driver is tested on the
-- batched capability receive path that current hubs always provide.
--
-- The driver has no wrappers of its own that catch and log handler errors, so there are no
-- `set_fail_on_caught_errors` patterns to add to the framework's defaults.
test.set_test_coroutine_priority(true)
test.set_capability_batch_receive(true)
-- The mock speaker never answers the driver's WebSocket keepalive pings, and a driver that has lost
-- its speaker retries forever, so end each test soon after its body instead of letting the driver
-- run on for the default hour of mock time.
test.set_post_body_time_budget(5)

-- hl_websocket.lua reports a WebSocket error (for instance a keepalive that gets no reply) with
-- `log.err`, which the real log module doesn't have (its level is `error`); the call raises
-- "attempt to call a nil value (field 'err')" in the listener thread instead of marking the device
-- offline and reconnecting. This stand-in lets those paths run as the driver intends. DRIVER BUG:
-- remove it once hl_websocket.lua calls `log.error`.
require("log").err = require("log").error

--- Shared fixtures for the Harman Luxury tests: a speaker (its HTTP API on port 80 and its
--- WebSocket on port 50002, as two mock addresses), the mDNS record that announces it, and the
--- server side of the WebSocket protocol the driver talks to it with.
---
--- The mock WebSocket server is minimal: the framework has no WebSocket support, so a speaker
--- completes the upgrade handshake with `accept_upgrade` and then exchanges unfragmented text
--- frames (`text_frame` for what the speaker sends, `client_frames` to read what the driver sent).
---
local M = {}

M.IP = "192.168.1.60"
M.MAC = "AA:BB:CC:DD:EE:10"
M.DNI = "aabbccddee10" -- M.MAC with its separators stripped, lowercased
M.MAC_B = "AA:BB:CC:DD:EE:11" -- a second speaker
M.DNI_B = "aabbccddee11"
M.TOKEN = "tok-1"
M.WS_PORT = 50002

-- `disco` keeps which speakers it already tried to add in a module-level table that nothing resets,
-- and `hl_websocket` holds a reference to `disco`. Loading both afresh for every test keeps one
-- test's discovery from deciding what the next one finds.
test.add_test_env_setup_func(function()
  package.loaded["disco"] = nil
  package.loaded["hl_websocket"] = nil
end)

--- The mDNS discovery event for a speaker, as the driver's discovery scan receives it.
---
--- @param ip string
--- @param mac string the speaker's MAC address (it becomes the device network id)
--- @param opts table|nil `{ setup_id = "604", mnid = "0BE8", name = "Speaker" }`; the defaults are
---   the MA510 model
--- @return table
function M.mdns_event(ip, mac, opts)
  opts = opts or {}
  local function bytes(s) return { s:byte(1, -1) } end
  return test.mock_mdns.build_event({
    name = opts.name or "Speaker",
    service_type = "_sue-st._tcp",
    domain = "local",
    address = ip,
    port = 80,
    txt = {
      bytes("mac=" .. mac),
      bytes("mnid=" .. (opts.mnid or "0BE8")),
      bytes("setupid=" .. (opts.setup_id or "604")),
    },
  })
end

--- The query string the driver sends for `GetData` of a path.
function M.get_data_query(path)
  return "path=" .. path:gsub("[^%w]", function(c) return string.format("%%%02X", c:byte()) end) .. "&roles=value"
end

--- A JSON string response body. `http.json` sends a string as it is (it takes a string to be JSON
--- text already), so the string is encoded first.
function M.json_string(value)
  return http.json(json.encode(value))
end

--- The body of a `getData` reply holding a string.
function M.string_value(value)
  return { { type = "string_", string_ = value } }
end

--- A speaker on the network: its HTTP API (port 80) and its WebSocket (port 50002).
---
--- The HTTP API answers, for every test in the file:
---   - the activation of a new credential token (`/api/setData`, which `Discovery` uses to pair),
---   - the speaker's name, and the token currently active (which the driver asks for before it
---     reconnects a WebSocket).
--- A test overrides any of them with `http.expect_request(speaker.api, ..., { prepend = true })`.
---
--- Each test must call `speaker:activate()` from its `test_init` (a test's own `test_init` replaces
--- the file's).
---
--- @param ip string
--- @param opts table|nil `{ label = "Kitchen", token = M.TOKEN }`
--- @return table `{ ip, label, token, api, ws, api_scenario, ws_scenario, activate }`
function M.new_speaker(ip, opts)
  opts = opts or {}
  local speaker = { ip = ip, label = opts.label or "Kitchen", token = opts.token or M.TOKEN }

  speaker.api_scenario = connection_scenario.new({ host = ip, port = 80 })
  speaker.api = speaker.api_scenario:connection("api", { matcher = http.matcher("GET", "^/api/") })
  http.expect_request(speaker.api, "GET", "/api/setData", { body = M.json_string(speaker.token), reusable = true })
  http.expect_request(speaker.api, "GET", "/api/getData", {
    query = M.get_data_query("settings:/deviceName"), body = M.string_value(speaker.label), reusable = true,
  })
  http.expect_request(speaker.api, "GET", "/api/getData", {
    query = M.get_data_query("settings:/smartthings/userToken"), body = M.string_value(speaker.token), reusable = true,
  })

  speaker.ws_scenario = connection_scenario.new({ host = ip, port = M.WS_PORT })
  speaker.ws = speaker.ws_scenario:connection("ws", {
    matcher = http.matcher("GET", "^/$"), framer = M.ws_framer,
  })

  function speaker:activate()
    self.api_scenario:activate()
    self.ws_scenario:activate()
  end
  return speaker
end

--- Read the client (masked) frames in `bytes` from `pos`.
--- @return table[] frames `{ opcode, text }`
--- @return number next_pos where an incomplete frame (or the end of `bytes`) starts
local function parse_client_frames(bytes, pos)
  local frames = {}
  while pos + 1 <= #bytes do
    local b0, b1 = bytes:byte(pos, pos + 1)
    local len, p = b1 & 0x7f, pos + 2
    if len == 126 then
      if p + 1 > #bytes then break end
      len = (bytes:byte(p) << 8) | bytes:byte(p + 1)
      p = p + 2
    end
    if p + 3 + len > #bytes then break end
    local mask = { bytes:byte(p, p + 3) }
    p = p + 4
    local chars = {}
    for k = 1, len do
      chars[k] = string.char(bytes:byte(p + k - 1) ~ mask[(k - 1) % 4 + 1])
    end
    table.insert(frames, { opcode = b0 & 0x0f, text = table.concat(chars) })
    pos = p + len
  end
  return frames, pos
end

--- The framer of a WebSocket connection (see `connection_scenario`'s `framer`): the one HTTP request
--- that upgrades it is a request for the scenario to answer; the frames after it are not requests,
--- so they are consumed without being answered (read them with `client_frames`).
function M.ws_framer(bytes, state)
  local requests, consumed = {}, 0
  if not state.upgraded then
    requests, consumed = http.frame_requests(bytes)
    if #requests == 0 then
      return requests, 0
    end
    state.upgraded = true
  end
  local _, next_pos = parse_client_frames(bytes, consumed + 1)
  return requests, next_pos - 1
end

--- Expect the driver's WebSocket upgrade request (one more each call) and hold it, to be completed
--- with `accept_upgrade`. Call it from `test_init`: the driver connects while it starts, before the
--- test body runs.
--- @return table the expectation
function M.expect_upgrade(speaker)
  return http.expect_request_for_test(speaker.ws, "GET", "/", { defer = true })
end

--- Complete the WebSocket upgrade for the request held by `expect_upgrade`.
--- @param within number|nil mock seconds to wait for the request
--- @return table the upgrade request
function M.accept_upgrade(expectation, within)
  local req = expectation:await({ within = within })
  req:respond({ status = 101, headers = {
    Upgrade = "websocket", Connection = "Upgrade",
    ["Sec-WebSocket-Accept"] = key_lib.build_accept_from(req.headers["sec-websocket-key"]),
  } })
  return req
end

--- A text frame the speaker sends the driver (server frames are unmasked).
--- @param payload string|table text, or a value to send as JSON
function M.text_frame(payload)
  if type(payload) == "table" then payload = json.encode(payload) end
  local n = #payload
  if n < 126 then
    return string.char(0x81, n) .. payload
  end
  return string.char(0x81, 126, n >> 8, n & 0xff) .. payload
end

--- The text frames the driver sent on a WebSocket connection, in order, after its upgrade request.
--- @param conn table a physical connection, e.g. `speaker.ws:connection()`
--- @return string[]
function M.client_frames(conn)
  local sent = conn:sent()
  local header_end = sent:find("\r\n\r\n", 1, true)
  if not header_end then return {} end
  local frames = parse_client_frames(sent, header_end + 4)
  local texts = {}
  for _, frame in ipairs(frames) do
    if frame.opcode == 0x1 then table.insert(texts, frame.text) end
  end
  return texts
end

--- How many frames with this opcode the driver sent on a WebSocket connection (0x8 is a close,
--- 0x9 a ping), after its upgrade request.
function M.count_frames(conn, opcode)
  local sent = conn:sent()
  local header_end = sent:find("\r\n\r\n", 1, true)
  local count = 0
  for _, frame in ipairs(header_end and parse_client_frames(sent, header_end + 4) or {}) do
    if frame.opcode == opcode then count = count + 1 end
  end
  return count
end

--- How many keepalive pings the driver sent on a WebSocket connection.
function M.count_pings(conn)
  return M.count_frames(conn, 0x9)
end

--- The decoded JSON messages the driver sent on a WebSocket connection (see `client_frames`).
function M.client_messages(conn)
  local messages = {}
  for _, text in ipairs(M.client_frames(conn)) do
    table.insert(messages, json.decode(text))
  end
  return messages
end

--- A mock Harman Luxury speaker device. Give each test its own `dni` unless its driver state is
--- reset.
--- @param dni string|nil
--- @return table
function M.new_device(dni)
  return test.mock_device.build_test_lan_device({
    label = "Kitchen", device_network_id = dni or M.DNI,
    profile = t_utils.get_profile_definition("harman-luxury.yaml"),
  })
end

--- Persist the fields the driver's `added` handler stores (a device the driver already knew before
--- it restarted).
function M.seed(device, ip, token)
  device:set_field("device_ipv4", ip or M.IP, { persist = true })
  device:set_field("credential", token or M.TOKEN, { persist = true })
end

return M
