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

local OpCode = require "lustre.frame.opcode"
local U16_MAX = 0xFFFF

---@class FrameHeader
---@field public fin boolean is finished
---@field public rsv1 boolean
---@field public rsv2 boolean
---@field public rsv3 boolean
---@field public masked boolean
---@field public opcode OpCode
---@field public length number|nil Length of the payload of this Frame
---@field public mask number[]|nil
---@field private length_length number Length of the length property (0-8)
---@field private mask_length number Length of the mask property (0-4)
local FrameHeader = {}
FrameHeader.__index = FrameHeader

---Decode an array of bytes into an integer
---
---note: The lua number type limitations apply, two's compliment
---wrapping of positive to negative numbers begins at the top of the 64th bit
---@param bytes integer[] The bytes to decode
---@return integer
local function decode_uint(bytes)
  local ret = 0
  for i, v in ipairs(bytes) do ret = (ret << 8) | v end
  return ret
end

---Extract a single u8 from the provided `v` with a specified start
---@param v integer The number to extract from
---@param start integer What bit to start at
---@return integer @ should always be between 0 and 255
local function extract_u8(v, start) return (v >> start) & 255 end

---Convert a value into an array of bytes with the provided length
---@param v integer
---@param n_bytes integer
---@return integer[] @ array of u8s
local function encode_uint(v, n_bytes)
  local ret = {}
  for i = n_bytes - 1, 0, -1 do
    local byte = extract_u8(v, i * 8)
    table.insert(ret, byte)
  end
  return ret
end

---Decode the length property, which if below 126, will just be `byte`
---when 126, it will be a 16bit integer, when 127 will be a 64bit integer
---(most significant bit must be 0)
---@param byte integer
---@param bytes integer[] The following bytes
---@return integer @The decoded value
---@return integer @The length of the decoded value (0, 2 or 8)
local function decode_len(byte, bytes)
  local len_byte = byte & 0x7f
  if len_byte < 126 then return len_byte, 0 end
  local extra_bytes = {}
  if len_byte == 126 then
    extra_bytes = table.pack(string.byte(bytes, 1, 2))
    if #extra_bytes < 2 then return nil, 2 end
    return (extra_bytes[1] << 8) | extra_bytes[2], 2
  elseif len_byte == 127 then
    extra_bytes = table.pack(string.byte(bytes, 1, 8))
    if #extra_bytes < 8 then return nil, 8 end
    local u64 = decode_uint(extra_bytes)
    -- Most significant bit means we found an invalid value, return nil
    if u64 < 0 then return nil, 8 end
    return u64, 8
  end
end

local function decode_len_stream(byte, socket)
  local len_byte = byte & 0x7f
  if len_byte < 126 then return len_byte, 0 end
  local extra_bytes = {}
  if len_byte == 126 then
    local next_2_bytes = assert(socket:receive(2))
    extra_bytes = table.pack(string.byte(next_2_bytes, 1, 2))
    assert(#extra_bytes >= 2, "Too few length bytes")
    return (extra_bytes[1] << 8) | extra_bytes[2], 2
  elseif len_byte == 127 then
    local bytes = assert(socket:receive(8))
    extra_bytes = table.pack(string.byte(bytes, 1, 8))
    assert(#extra_bytes >= 8)
    local u64 = decode_uint(extra_bytes)
    -- Most significant bit means we found an invalid value, return nil
    if u64 < 0 then return nil, 8 end
    return u64, 8
  end
end

---Decode the mask bytes into a 4 byte array
---@param bytes string
---@return integer[]|nil
local function decode_mask(bytes)
  local mask = table.pack(string.byte(bytes, 1, 4))
  if #mask < 4 then return end
  return mask
end

local function decode_mask_stream(socket)
  local bytes = assert(socket:receive(4))
  local mask = table.pack(string.byte(bytes, 1, 4))
  if #mask < 4 then return end
  return mask
end

---Decode the header in total
---@param bytes string The byte string to decode (should be at least 2 bytes long)
---@return table
local function decode_header(bytes)
  local idx = 1
  local first_byte, second_byte = string.byte(bytes, idx, 2)
  idx = idx + 2
  local fin = first_byte & 0x80 ~= 0
  local rsv1 = first_byte & 0x40 ~= 0
  local rsv2 = first_byte & 0x20 ~= 0
  local rsv3 = first_byte & 0x10 ~= 0
  local opcode = OpCode.decode(first_byte & 0x0f)
  local masked = (second_byte & 0x80) ~= 0
  local length, length_length = decode_len(second_byte, string.sub(bytes, idx))
  idx = idx + length_length
  local mask
  if masked then mask = decode_mask(string.sub(bytes, idx)) end
  return {
    fin = fin,
    rsv1 = rsv1,
    rsv2 = rsv2,
    rsv3 = rsv3,
    opcode = opcode,
    masked = masked,
    length = length,
    length_length = length_length,
    mask_length = (mask and 4) or 0,
    mask = mask,
  }
end

local function decode_header_stream(socket)
  local bytes = assert(socket:receive(2))
  local first_byte, second_byte = string.byte(bytes, 1, 2)
  local fin = first_byte & 0x80 ~= 0
  local rsv1 = first_byte & 0x40 ~= 0
  local rsv2 = first_byte & 0x20 ~= 0
  local rsv3 = first_byte & 0x10 ~= 0
  local opcode = OpCode.decode(first_byte & 0x0f)
  local masked = (second_byte & 0x80) ~= 0
  local length, length_length = decode_len_stream(second_byte, socket)
  local mask
  if masked then mask = decode_mask_stream(socket) end
  return {
    fin = fin,
    rsv1 = rsv1,
    rsv2 = rsv2,
    rsv3 = rsv3,
    opcode = opcode,
    masked = masked,
    length = length,
    length_length = length_length,
    mask_length = (mask and 4) or 0,
    mask = mask,
  }
end

function FrameHeader.from_stream(socket)
  local s, t = pcall(decode_header_stream, socket)
  if not s then return nil, t end
  return setmetatable(t, FrameHeader)
end

---Decode a string into a FrameHeader
---@param bytes string
---@return FrameHeader|nil
---@return nil|string @error message
function FrameHeader.decode(bytes)
  if #bytes < 2 then return nil, "Expected at least 2 bytes for the frame header" end
  local header = decode_header(bytes)
  return setmetatable(header, FrameHeader)
end

---Get the total length of this header, including the length of anyway
---included mask and the length of the payload length
---@return number
function FrameHeader:len() return 2 + self.mask_length + self.length_length end

---Get the payload's length from this header
---@return integer|nil
function FrameHeader:payload_len() return self.length end

---Encode this header into a a string
---@return string|nil, string|nil
function FrameHeader:encode()
  if self.length == nil then return nil, "Invalid length" end
  local bytes = {0, 0}
  if self.fin then bytes[1] = bytes[1] | 0x80 end
  if self.rsv1 then bytes[1] = bytes[1] | 0x40 end
  if self.rsv2 then bytes[1] = bytes[1] | 0x20 end
  if self.rsv3 then bytes[1] = bytes[1] | 0x10 end
  bytes[1] = bytes[1] | self.opcode:encode()
  if self.mask then bytes[2] = bytes[2] | 0x80 end
  if self.length_length == 0 then
    bytes[2] = bytes[2] | self.length
  else
    if self.length_length < 8 then
      bytes[2] = bytes[2] | 126
    else
      bytes[2] = bytes[2] | 127
    end
    for _, byte in ipairs(encode_uint(self.length, self.length_length)) do
      table.insert(bytes, byte)
    end
  end
  for _, byte in ipairs(self.mask or {}) do table.insert(bytes, byte) end
  return string.char(table.unpack(bytes))
end

function FrameHeader:is_masked() return self.masked end

-- #Builder

---Create a default FrameHeader
---@return FrameHeader
function FrameHeader.default()
  return setmetatable({
    fin = true,
    rsv1 = false,
    rsv2 = false,
    rsv3 = false,
    opcode = OpCode.decode(8),
    length = 0,
    length_length = 0,
    masked = false,
    mask_length = 0,
    mask = nil,
  }, FrameHeader)
end

---Set the "is final" bit (default true)
---@param value boolean
---@return FrameHeader
function FrameHeader:set_fin(value)
  self.fin = value
  return self
end

---Set the reserved bit 1 (default false)
---@param value boolean
---@return FrameHeader
function FrameHeader:set_rsv1(value)
  self.rsv1 = value
  return self
end

---Set the reserved bit 2 (default false)
---@param value boolean
---@return FrameHeader
function FrameHeader:set_rsv2(value)
  self.rsv2 = value
  return self
end

---Set the reserved bit 3 (default false)
---@param value boolean
---@return FrameHeader
function FrameHeader:set_rsv3(value)
  self.rsv3 = value
  return self
end

---Set the opcode for this header (default 8/control-close)
---@param value integer|OpCode
---@return FrameHeader
function FrameHeader:set_opcode(value)
  if type(value) == "number" then
    self.opcode = OpCode.decode(value)
  else
    self.opcode = value
  end
  return self
end

---Set the payload length for this header (default 0)
---@param value integer
---@return FrameHeader
function FrameHeader:set_length(value)
  if value < 126 then
    self.length_length = 0
  elseif value <= U16_MAX then
    self.length_length = 2
  else
    self.length_length = 8
  end
  self.length = value
  return self
end

---Set the mask for encoding this header (default nil)
---@param value number[]|nil
---@return FrameHeader
function FrameHeader:set_mask(value)
  self.mask_length = value and 4
  if self.mask_length ~= 4 then return nil, "Failed to set mask, must be 4 bytes" end
  self.masked = value ~= nil
  self.mask = value
  return self
end

return FrameHeader
