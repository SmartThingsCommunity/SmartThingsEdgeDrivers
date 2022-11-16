--  Copyright 2021 SmartThings
--
--  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
--  except in compliance with the License. You may obtain a copy of the License at:
--
--      http://www.apache.org/licenses/LICENSE-2.0
--
--  Unless required by applicable law or agreed to in writing, software distributed under the
--  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
--  either express or implied. See the License for the specific language governing permissions
--  and limitations under the License.
--

---@class OpCode
---@field public type string
---@field public sub string
---@field public value number|nil
local OpCode = {}
OpCode.__index = OpCode

function OpCode.decode(n)
  local ret = {}
  if n == 0 then
    ret.type = "data"
    ret.sub = "continue"
  elseif n == 1 then
    ret.type = "data"
    ret.sub = "text"
  elseif n == 2 then
    ret.type = "data"
    ret.sub = "binary"
  elseif n >= 3 and n <= 7 then
    ret.type = "data"
    ret.sub = "reserved"
    ret.value = n
  elseif n == 8 then
    ret.type = "control"
    ret.sub = "close"
  elseif n == 9 then
    ret.type = "control"
    ret.sub = "ping"
  elseif n == 10 then
    ret.type = "control"
    ret.sub = "pong"
  elseif n <= 15 then
    ret.type = "control"
    ret.sub = "reserved"
    ret.value = n
  else
    return nil, "OpCode out of range"
  end
  return setmetatable(ret, OpCode)
end

function OpCode:encode()
  if self.value then return self.value end
  if self.type == "data" then
    if self.sub == "continue" then return 0 end
    if self.sub == "text" then return 1 end
    if self.sub == "binary" then return 2 end
  end
  if self.type == "control" then
    if self.sub == "close" then return 8 end
    if self.sub == "ping" then return 9 end
    if self.sub == "pong" then return 10 end
  end
  return nil, "Invalid opcode"
end

function OpCode.ping() return OpCode.from("control", "ping") end

function OpCode.pong() return OpCode.from("control", "pong") end

function OpCode.close() return OpCode.from("control", "close") end

function OpCode.continue() return OpCode.from("data", "continue") end

function OpCode.text() return OpCode.from("data", "text") end

function OpCode.binary() return OpCode.from("data", "binary") end

function OpCode.from(ty, sub, value)
  return setmetatable({type = ty, sub = sub, value = value}, OpCode)
end

return OpCode
