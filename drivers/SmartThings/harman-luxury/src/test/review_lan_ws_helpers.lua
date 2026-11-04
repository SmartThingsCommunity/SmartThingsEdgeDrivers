-- Helpers shared by the review tests: a harman speaker device fixture + a minimal websocket server side
-- built on the mock TCP connection (the framework has no websocket support, so handshake and framing are by hand).
local test = require "integration_test"
test.set_test_coroutine_priority(true)
test.set_capability_batch_receive(true)
require "test.review_lan_http_shim"

local t_utils = require "integration_test.utils"
local connection_scenario = require "integration_test.connection_scenario"
local http = require "integration_test.connection_scenario_http"
local key_lib = require "lustre.handshake.key"
local json = require "st.json"
require("log").err = function(...) print("LOG.ERR", ...) end

local H = {}
H.IP = "192.168.1.60"
H.TOKEN = "tok-1"

function H.new_device(dni)
  local dev = test.mock_device.build_test_lan_device({
    label = "Kitchen", device_network_id = dni or "aabbccddee10",
    profile = t_utils.get_profile_definition("harman-luxury.yaml"),
  })
  return dev
end

--- Seed the fields an earlier `added` persisted (a driver restart), as the Hue tests do.
function H.seed(dev, ip)
  dev:set_field("device_ipv4", ip or H.IP, { persist = true })
  dev:set_field("credential", H.TOKEN, { persist = true })
end

function H.ws_scenario(ip)
  local scenario = connection_scenario.new({ host = ip or H.IP, port = 50002 })
  local ws = scenario:connection("ws", { matcher = http.matcher("GET", "^/$") })
  return scenario, ws
end

--- Complete the websocket upgrade for the request the driver just sent (a masked-client / unmasked-server ws).
--- The driver's thread connects during startup, before the test body runs, so the upgrade request is
--- registered (deferred) from test_init via H.expect_upgrade(ws) and awaited here.
function H.expect_upgrade(ws)
  return http.expect_request_for_test(ws, "GET", "/", { defer = true })
end

function H.accept_upgrade(exp)
  local req = exp:await()
  req:respond({ status = 101, headers = {
    Upgrade = "websocket", Connection = "Upgrade",
    ["Sec-WebSocket-Accept"] = key_lib.build_accept_from(req.headers["sec-websocket-key"]),
  } })
  return req
end

--- server -> client text frame (unmasked)
function H.text_frame(payload)
  if type(payload) == "table" then payload = json.encode(payload) end
  local n = #payload
  local hdr
  if n < 126 then hdr = string.char(0x81, n)
  else hdr = string.char(0x81, 126, n >> 8, n & 0xff) end
  return hdr .. payload
end

--- decode the (masked) text frames the driver sent on a connection handle (after the HTTP upgrade request)
function H.client_frames(conn_handle)
  local sent = conn_handle:sent()
  local pos = sent:find("\r\n\r\n", 1, true)
  local out = {}
  if not pos then return out end
  local i = pos + 4
  while i <= #sent do
    local b0, b1 = sent:byte(i, i + 1)
    local opcode, len, p = b0 & 0x0f, b1 & 0x7f, i + 2
    if len == 126 then len = (sent:byte(p) << 8) | sent:byte(p + 1); p = p + 2 end
    local mask = { sent:byte(p, p + 3) }; p = p + 4
    local chars = {}
    for k = 1, len do chars[k] = string.char(sent:byte(p + k - 1) ~ mask[(k - 1) % 4 + 1]) end
    table.insert(out, { opcode = opcode, text = table.concat(chars) })
    i = p + len
  end
  return out
end

return H
