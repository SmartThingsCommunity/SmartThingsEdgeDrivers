-- WORKAROUND for a framework gap: integration_test.mock_socket stubs luasocket's protect/skip/try/
-- newtry/source/sink/sourcet/sinkt as no-ops, so `cosock.asyncify "socket.http"` (LuaSocket's HTTP client,
-- used by this driver) loads without `request`. This re-implements the pure-Lua parts so the real
-- LuaSocket http.lua can run over the mock TCP socket. Require AFTER integration_test, BEFORE the driver.
local mock_socket = require "integration_test.mock_socket"
local cosock_socket = require "cosock.socket"

local function protect(f)
  return function(...)
    local r = table.pack(pcall(f, ...))
    if r[1] then return table.unpack(r, 2, r.n) end
    if type(r[2]) == "table" then return nil, r[2][1] end
    error(r[2], 0)
  end
end
local function newtry(finalizer)
  return function(...)
    local first = ...
    if first then return ... end
    local _, err = ...
    if finalizer then finalizer() end
    error({ err }, 2)
  end
end
local function skip(n, ...) return select(n + 1, ...) end

local sinkt = {
  ["keep-open"] = function(sock) return function(chunk, err) if chunk then return sock:send(chunk) end return 1 end end,
  ["close-when-done"] = function(sock)
    return function(chunk, err) if chunk then return sock:send(chunk) end sock:close() return 1 end
  end,
}
local sourcet = {
  ["by-length"] = function(sock, length)
    return function()
      if length <= 0 then return nil end
      local chunk, err = sock:receive(length)
      if err then return nil, err end
      length = length - #chunk
      return chunk
    end
  end,
  ["until-closed"] = function(sock)
    local done
    return function()
      if done then return nil end
      local chunk, err, partial = sock:receive("*a")
      if err == "closed" or err == nil then done = true; return (chunk and #chunk > 0 and chunk) or partial or nil end
      return nil, err
    end
  end,
}
local function sink(mode, sock) return sinkt[mode](sock) end
local function source(mode, sock, length) return sourcet[mode](sock, length) end
local function try(...) return newtry()(...) end

for _, m in ipairs({ mock_socket, cosock_socket }) do
  rawset(m, "protect", protect); rawset(m, "newtry", newtry); rawset(m, "skip", skip)
  rawset(m, "try", try); rawset(m, "sink", sink); rawset(m, "source", source)
  rawset(m, "sinkt", sinkt); rawset(m, "sourcet", sourcet)
end
return true
