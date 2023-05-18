---@class OpCode
---@field public type string ["data"|"control"] The primary type of this frame
---@field public sub string ["continue"|"text"|"binary"|"reserved"|"ping"|"pong"] The sub type of this frame
---@field public value number|nil Only used for reserved frames
local OpCode = {}
OpCode.__index = OpCode
OpCode.__tostring = function(self)
  if self.sub then
    return string.format("%s:%s", self.type,
      self.sub)
  end
  return self.type
end

---Decode a bytes into its Opcode
---@param n integer The raw opcode from the incoming stream
---@return OpCode
---@return string|nil @if OpCode is nil, this will be the error message
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
  if self.value then
    return self.value
  end
  if self.type == "data" then
    if self.sub == "continue" then
      return 0
    end
    if self.sub == "text" then
      return 1
    end
    if self.sub == "binary" then
      return 2
    end
  end
  if self.type == "control" then
    if self.sub == "close" then
      return 8
    end
    if self.sub == "ping" then
      return 9
    end
    if self.sub == "pong" then
      return 10
    end
  end
  return nil, "Invalid opcode"
end

---Convenience Constructor for ping
---@return OpCode
function OpCode.ping()
  return OpCode.from("control", "ping")
end

---Convenience Constructor for pong
---@return OpCode
function OpCode.pong()
  return OpCode.from("control", "pong")
end

---Convenience Constructor for close
---@return OpCode
function OpCode.close()
  return OpCode.from("control", "close")
end

---Convenience Constructor for continue
---@return OpCode
function OpCode.continue()
  return OpCode.from("data", "continue")
end

---Convenience Constructor for text
---@return OpCode
function OpCode.text()
  return OpCode.from("data", "text")
end

---Convenience Constructor for binary
---@return OpCode
function OpCode.binary()
  return OpCode.from("data", "binary")
end

---Convenience Constructor to build from parts
---@return OpCode
function OpCode.from(ty, sub, value)
  return setmetatable({
    type = ty,
    sub = sub,
    value = value,
  }, OpCode)
end

---Check if this opcode's sub typ is "continue"
---@return boolean
function OpCode:is_continue()
  return self.sub == "continue"
end

---Check if this opcode can be continued (self.sub needs to either be
--- "text" or "binary")
---@return boolean
function OpCode:can_continue()
  return self.sub == "continue" or self.sub
           == "text" or self.sub == "binary"
end

return OpCode
