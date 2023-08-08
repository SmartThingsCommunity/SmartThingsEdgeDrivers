-- Copyright 2021 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
local m = {}
local log = require "log"
local unpack = table.unpack
local pack = table.pack

local function maybe_transform_output(ret, transform)
  if transform.output then
    return transform.output(unpack(ret, 1, ret.n))
  end
  return unpack(ret, 1, ret.n)
end

local function assert_fmt(test, msg, ...)
  if not test then
    error(string.format(msg, ...), 2)
  end
end


function m.passthroughbuilder(recvmethods, sendmethods)
  return function(method, transformsrc)
    return function(self, ...)
      local transform = transformsrc
      if type(transform) == "function" then transform = transform() end
      if transform then
        assert(type(transform) == "table", "transformer must be table or function that returns table")
        assert(not transform.input or type(transform.input) == "function", "input transformer not a function")
        assert(not transform.blocked or type(transform.blocked) == "function", "blocked transformer not a function")
        assert(not transform.output or type(transform.output) == "function", "output transformer not a function")
      else
        transform = {}
      end

      local inputparams = pack(...)

      if transform.input then
        inputparams = pack(transform.input(unpack(inputparams, 1, inputparams.n)))
      end

      repeat
        local isock = self.inner_sock
        local ret = pack(isock[method](isock, unpack(inputparams, 1, inputparams.n)))
        local status = ret[1]
        local err = ret[2]
        if status == nil and err == nil then
          log.warn_with({ hub_logs = true }, string.format(
            "Called %q on %q which returned nil, nil",
            method or nil, self.class or self.inner_sock and self.inner_sock.class or "unknown socket"
          ))
          local all_rets = {}
          for _,v in ipairs(ret) do
            table.insert(all_rets, string.format("%q", v or nil))
          end
          log.debug_with({ hub_logs = true }, "All return values:", table.concat(all_rets, ", "))
        end
        if not status and err and ((recvmethods[method] or {})[err] or (sendmethods[method] or {})[err]) then
          if transform.blocked then
            inputparams = pack(transform.blocked(unpack(ret, 1, ret.n)))
          end
          local kind = ((recvmethods[method] or {})[err]) and "recvr" or ((sendmethods[method] or {})[err]) and "sendr"
          assert_fmt(kind, "about to yield on method (%s) that is niether recv nor send", method)
          local recvr, sendr, rterr = coroutine.yield(kind == "recvr" and { self } or {},
            kind == "sendr" and { self } or {},
            self.timeout)

          -- woken, unset waker
          self.wakers[kind] = nil

          if rterr then
            if rterr == err then
              return maybe_transform_output(ret, transform)
            else
              return maybe_transform_output(pack(nil, rterr), transform)
            end
          end

          if kind == "recvr" then
            assert_fmt(
              recvr and #recvr == 1,
              "thread resumed without awaited socket or error (or too many sockets): \
                    method:%q, kind:%q, err:%q rterr:%q recvr:%q sendr: %q",
              method or nil,
              kind or nil,
              err or nil,
              rterr or nil,
              (recvr and #recvr) or nil,
              (sendr and #sendr) or nil)
            assert_fmt(
              sendr == nil or #sendr == 0,
              "thread resumed with unexpected socket: method:%q, kind:%q, err:%q rterr:%q recvr:%q sendr: %q",
              method or nil,
              kind or nil,
              err or nil,
              rterr or nil,
              (recvr and #recvr) or nil,
              (sendr and #sendr) or nil)
          else
            assert_fmt(
              recvr == nil or #recvr == 0,
              "thread resumed with unexpected socket:%q, kind:%q, err:%q rterr:%q recvr: %q sendr: %q",
              method or nil,
              kind or nil,
              err or nil,
              rterr or nil,
              (recvr and #recvr) or nil,
              (sendr and #sendr) or nil)
            assert_fmt(
              sendr and #sendr == 1,
              "thread resumed without awaited socket or error (or too many sockets): \
                    method:%q, kind:%q, err:%q rterr:%q recvr:%q sendr: %q",
              method or nil,
              kind or nil,
              err or nil,
              rterr or nil,
              (recvr and #recvr) or nil,
              (sendr and #sendr) or nil)
          end
        elseif status then
          self.class = self.inner_sock.class
          return maybe_transform_output(ret, transform)
        else
          return maybe_transform_output(ret, transform)
        end
      until nil
    end
  end
end

function m.setuprealsocketwaker(socket, kinds)
  kinds = kinds or { "sendr", "recvr" }
  local kindmap = {}
  for _, kind in ipairs(kinds) do kindmap[kind] = true end

  socket.setwaker = function(self, kind, waker)
    assert(kindmap[kind], "unsupported wake kind: " .. tostring(kind))
    self.wakers = self.wakers or {}
    assert((not waker) or (not self.wakers[kind]),
      tostring(kind) .. " waker already set, sockets can only block one thread per waker kind")
    self.wakers[kind] = waker
  end

  socket._wake = function(self, kind, ...)
    local wakers = self.wakers or {}
    if wakers[kind] then
      wakers[kind](...)
      wakers[kind] = nil
      return true
    else
      print("warning attempt to wake, but no waker set")
      return false
    end
  end
end

return m
