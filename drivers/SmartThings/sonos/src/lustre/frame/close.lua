---@class CloseCode
---@field public value integer The numeric code for this close reason
---@field public type string The human friendly close reason
local CloseCode = {}
CloseCode.__index = CloseCode

---@class CloseFrame
---@field public code CloseCode The close reason
---@field public reason string The frame's body which may provide more context to the close code
local CloseFrame = {}
CloseFrame.__index = CloseFrame

---Things closed normally
---@return CloseCode
function CloseCode.normal()
  return CloseCode.from_int(1000)
end
---Server endpoint is going away
---@return CloseCode
function CloseCode.away()
  return CloseCode.from_int(1001)
end

---Protocol based error
---@return CloseCode
function CloseCode.protocol()
  return CloseCode.from_int(1002)
end
---Payload is unsupported
---@return CloseCode
function CloseCode.unsupported()
  return CloseCode.from_int(1003)
end
---No close code was provided in a close frame
---@return CloseCode
function CloseCode.status()
  return CloseCode.from_int(1005)
end
---An abnormal closure
---@return CloseCode
function CloseCode.abnormal()
  return CloseCode.from_int(1006)
end
---Payload is invalid
---@return CloseCode
function CloseCode.invalid()
  return CloseCode.from_int(1007)
end
---Policy violation
---@return CloseCode
function CloseCode.policy()
  return CloseCode.from_int(1008)
end
---payload too large
---@return CloseCode
function CloseCode.size()
  return CloseCode.from_int(1009)
end
---No expected extension returned from server
---@return CloseCode
function CloseCode.extension()
  return CloseCode.from_int(1010)
end
---Server error
---@return CloseCode
function CloseCode.error()
  return CloseCode.from_int(1011)
end
---Server is restarting
---@return CloseCode
function CloseCode.restart()
  return CloseCode.from_int(1012)
end
---Server is overloaded, try again later
---@return CloseCode
function CloseCode.again()
  return CloseCode.from_int(1013)
end
function CloseCode.tls()
  return CloseCode.from_int(1015)
end

function CloseCode.from_int(code)
  local ret = {value = code}
  if code == 1000 or nil then -- test if we actually need this
    ret.type = "normal"
  elseif code == 1001 then
    ret.type = "away"
  elseif code == 1002 then
    ret.type = "protocol"
  elseif code == 1003 then
    ret.type = "unsupported"
  elseif code == 1005 then
    ret.type = "status"
  elseif code == 1006 then
    ret.type = "abnormal"
  elseif code == 1007 then
    ret.type = "invalid"
  elseif code == 1008 then
    ret.type = "policy"
  elseif code == 1009 then
    ret.type = "size"
  elseif code == 1010 then
    ret.type = "extension"
  elseif code == 1011 then
    ret.type = "error"
  elseif code == 1012 then
    ret.type = "restart"
  elseif code == 1013 then
    ret.type = "again"
  elseif code == 1015 then
    ret.type = "tls"
  elseif code >= 1016 and code <= 2999 then
    ret.type = "reserved"
  elseif code >= 3000 and code <= 3999 then
    ret.type = "iana"
  elseif code >= 4000 and code <= 4999 then
    ret.type = "library"
  else
    ret.type = "bad"
  end
  return setmetatable(ret, CloseCode)
end

function CloseCode.decode(bytes)
  local one, two = string.byte(bytes, 1, 2)

  local int
  if one and two then
    int = one << 8 | two
  else
    int = 1000
  end
  return CloseCode.from_int(int)
end

function CloseCode:encode()
  local one = (self.value >> 8) & 255
  local two = self.value & 255
  return string.char(one, two)
end

function CloseFrame.decode(bytes)
  local one, two = string.byte(bytes, 1, 2)
  local code = one << 8 | two
  return CloseFrame.from_parts(code, string.sub(
    bytes, 3))
end

function CloseFrame.from_parts(code, reason)
  if type(code) == "number" then
    code = CloseCode.from_int(code)
  end
  return setmetatable({
    code = code or CloseCode.normal(),
    reason = reason or "",
  }, CloseFrame)
end

function CloseFrame:encode()
  return self.code:encode() .. self.reason
end

return {
  CloseCode = CloseCode,
  CloseFrame = CloseFrame,
}
