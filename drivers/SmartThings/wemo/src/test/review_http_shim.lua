-- TEST-SIDE SHIM (review of the LAN integration test framework).
--
-- The wemo driver does `cosock.asyncify "socket.http"` and calls `http.request{...}`. Under the
-- integration test framework `socket.protect` (and `newtry`, `try`, `sink`, `source`, `skip`) are
-- no-op mocks (integration_test/mock_socket.lua `func_mocks`), so luasocket's http.lua loads but
-- `http.request` is nil. This shim replaces `cosock.asyncify("socket.http")` with a small pure-Lua
-- HTTP/1.1 client over `cosock.socket.tcp`, matching the `request{}` contract wemo relies on
-- (`resp, code, headers, status_line`, `nil, err` on failure). It must be required before the driver loads.
local cosock = require "cosock"
local socket = require "cosock.socket"

local real_asyncify = cosock.asyncify

local function read_chunked(sock)
  local parts = {}
  while true do
    local size_line, err = sock:receive("*l")
    if not size_line then return nil, err end
    local size = tonumber(size_line:match("^(%x+)"), 16)
    if not size then return nil, "malformed chunk" end
    if size == 0 then
      sock:receive("*l")
      return table.concat(parts)
    end
    local data, derr = sock:receive(size)
    if not data then return nil, derr end
    table.insert(parts, data)
    sock:receive("*l") -- CRLF after chunk
  end
end

local http = {}

function http.request(reqt)
  local host, port, path = reqt.url:match("^http://([^:/]+):?(%d*)(/?.*)$")
  if path == "" then path = "/" end
  port = tonumber(port) or 80
  local sock = socket.tcp()
  sock:settimeout(60)
  local ok, cerr = sock:connect(host, port)
  if not ok then sock:close() return nil, cerr end

  local body = ""
  if reqt.source then
    local parts = {}
    while true do
      local chunk = reqt.source()
      if not chunk then break end
      table.insert(parts, chunk)
    end
    body = table.concat(parts)
  end
  local lines = { string.format("%s %s HTTP/1.1", reqt.method or "GET", path) }
  local has_host = false
  for k, v in pairs(reqt.headers or {}) do
    if k:lower() == "host" then has_host = true end
    table.insert(lines, k .. ": " .. tostring(v))
  end
  if not has_host then table.insert(lines, "Host: " .. host .. ":" .. port) end
  local _, serr = sock:send(table.concat(lines, "\r\n") .. "\r\n\r\n" .. body)
  if serr then sock:close() return nil, serr end

  local status_line, err = sock:receive("*l")
  if not status_line then sock:close() return nil, err end
  local code = tonumber(status_line:match("HTTP/%d%.%d (%d%d%d)"))
  local headers = {}
  while true do
    local line, herr = sock:receive("*l")
    if not line then sock:close() return nil, herr end
    if line == "" then break end
    local k, v = line:match("^(.-):%s*(.*)$")
    if k then headers[k:lower()] = v end
  end

  local resp_body, berr
  if headers["transfer-encoding"] and headers["transfer-encoding"]:lower():find("chunked") then
    resp_body, berr = read_chunked(sock)
  elseif headers["content-length"] then
    local n = tonumber(headers["content-length"])
    if n == 0 then resp_body = "" else resp_body, berr = sock:receive(n) end
  else
    local partial
    resp_body, berr, partial = sock:receive("*a")
    resp_body = resp_body or partial
    berr = nil
  end
  sock:close()
  if berr then return nil, berr end -- e.g. "closed" mid-chunked-body, as luasocket reports it

  if reqt.sink and resp_body and #resp_body > 0 then reqt.sink(resp_body) end
  if reqt.sink then reqt.sink(nil) end
  return 1, code, headers, status_line
end

cosock.asyncify = function(name, ...)
  if name == "socket.http" then return http end
  return real_asyncify(name, ...)
end

return http
