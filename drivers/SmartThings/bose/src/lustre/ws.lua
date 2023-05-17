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

local cosock = require "cosock"
local socket = require "cosock.socket"
local Request = require "luncheon.request"
local Response = require "luncheon.response"
local send_utils = require "luncheon.utils"
local Handshake = require "lustre.handshake"
local Key = require "lustre.handshake.key"
local Config = require "lustre.config"
local Frame = require "lustre.frame"
local FrameHeader = require "lustre.frame.frame_header"
local OpCode = require "lustre.frame.opcode"
local CloseCode = require"lustre.frame.close".CloseCode
local Message = require "lustre.message"
local log = require "log"

local utils = require "lustre.utils"

---@class WebSocket
---
---@field url string the endpoint to hit
---@field socket table lua socket
---@field handshake_key string key used in the websocket handshake
---@field config Config
---@field _tx table
---@field _rx table
local WebSocket = {}
WebSocket.__index = WebSocket

---Create new client object
---@param socket table connected tcp socket
---@param url string url to connect
---@param config Config
---@param message_cb function
---@param error_cb function
---@param close_cb function
---@return client WebSocket
---@return err string|nil
function WebSocket.client(socket, url, config, ...)
  local args = {...}
  local _tx, _rx = cosock.channel.new()
  local ret = setmetatable({
    is_client = true,
    socket = socket,
    url = url or "/",
    handshake_key = Key.generate_key(),
    config = config or Config.default(),
    _tx = _tx,
    _rx = _rx,
  }, WebSocket)
  ret:register_message_cb(args[1])
  ret:register_error_cb(args[2])
  ret:register_close_cb(args[3])
  return ret
end

function WebSocket.server(socket, config, ...) end

---@param cb function called when a complete message has been received
---@return self WebSocket
function WebSocket:register_message_cb(cb)
  if type(cb) == "function" then self.message_cb = cb end
  return self
end

---@param cb function called when there is an error
---@return self WebSocket
function WebSocket:register_error_cb(cb)
  if type(cb) == "function" then self.error_cb = cb end
  return self
end
---@param cb function called when the connection was closed
---@return self WebSocket
function WebSocket:register_close_cb(cb)
  if type(cb) == "function" then self.close_cb = cb end
  return self
end

---@param text string
---@return err string|nil
function WebSocket:send_text(text)
  local data_idx = 1
  local frames_sent = 0
  if self._close_frame_sent then return "currently closing connection" end
  repeat -- TODO fragmentation while sending has not been tested
    local header = FrameHeader.default()
    local payload = ""
    if (text:len() - data_idx + 1) > self.config._max_frame_size then header:set_fin(false) end
    payload = string.sub(text, data_idx, data_idx + self.config._max_frame_size)
    if data_idx ~= 1 then
      header:set_opcode(OpCode.continue())
    else
      header:set_opcode(OpCode.text())
    end
    header:set_length(#payload)
    local frame = Frame.from_parts(header, payload)
    frame:set_mask() -- todo handle client vs server
    local _, err = self._tx:send(frame)
    if err then return "channel error:" .. err end
    data_idx = data_idx + frame:payload_len()
    frames_sent = frames_sent + 1
  until text:len() <= data_idx
end

---@param bytes string
---@return bytes_sent number
---@return err string|nil
function WebSocket:send_bytes(bytes)
  local data_idx = 1
  local frames_sent = 0
  if self._close_frame_sent then return "currently closing connection" end
  repeat
    local header = FrameHeader.default()
    local payload = ""
    if (bytes:len() - data_idx + 1) > self.config._max_frame_size then header:set_fin(false) end
    payload = string.sub(bytes, data_idx, data_idx + self.config._max_frame_size)
    if data_idx ~= 1 then
      header:set_opcode(OpCode.continue())
    else
      header:set_opcode(OpCode.binary())
    end
    header:set_length(#payload)
    local frame = Frame.from_parts(header, payload)
    frame:set_mask() -- todo handle client vs server
    local _, err = self._tx:send(frame)
    if err then return "channel error:" .. err end
    data_idx = data_idx + frame:payload_len()
    frames_sent = frames_sent + 1
  until bytes:len() <= data_idx
end

--TODO remove the fragmentation code duplication in the `send_text` and `send_bytes` apis
--TODO  Could perhaps remove those apis entirely.
---@param message Message
---@return err string|nil
function WebSocket:send(message) return nil, "not implemented" end

---@return success number 1 if handshake was successful
---@return err string|nil
function WebSocket:connect(host, port)
  if not self.is_client then -- todo use metatables to enforce this
    return nil, "only a client can connect"
  end
  if not host or not port then return nil, "missing host or port" end

  local r, err = self.socket:connect(host, port)
  if not r then return nil, "socket connect failure: " .. err end

  -- Do handshake
  local req = Request.new("GET", self.url, self.socket)
  req:add_header("Connection", "Upgrade")
  req:add_header("Upgrade", "websocket")
  req:add_header("User-Agent", "lua-lustre")
  req:add_header("Sec-Websocket-Version", 13)
  req:add_header("Sec-Websocket-Key", self.handshake_key)
  req:add_header("Host", string.format("%s:%d", host, port))
  for _, prot in ipairs(self.config.protocols) do
    -- TODO I think luncheon should be able to handle multiple values, but
    -- it currently only sends the last value added
    req:add_header("Sec-Websocket-Protocol", prot)
  end
  local s, err = req:send()
  if not s then return "handshake request failure: " .. err end
  local res, err = Response.tcp_source(self.socket)
  if not res then return nil, "Upgrade response failure: " .. err end
  local handshake = Handshake.client(self.handshake_key, {}, {})
  local success, err = handshake:validate_accept(res)
  if not success then return nil, "invalid handshake: " .. err end
  cosock.spawn(function() self:receive_loop() end, "Client receive loop")
  return 1
end

function WebSocket:accept() end

---@param close_code CloseCode
---@param reason string
---@return success number 1 if succss
---@return err string|nil
function WebSocket:close(close_code, reason)
  local close_frame = Frame.close(close_code, reason):set_mask() -- TODO client vs server
  local suc, err = self._tx:send(close_frame)
  if not suc then return nil, "channel error:" .. err end
  return 1
end

---@return message Message
---@return err string|nil
function WebSocket:receive_loop()
  local partial_frames = {}
  local received_bytes = 0
  local frames_since_last_ping = 0
  local pending_pongs = 0
  local multiframe_message = false
  local msg_type
  while true do
    local recv, _, err = socket.select({self.socket, self._rx}, nil, self.config._keep_alive)
    if not recv then
      if err == "timeout" then
        if pending_pongs >= 2 then --TODO max number of pings without a pong could be configurable
          if self.error_cb then self.error_cb("no response to keep alive ping commands") end
          self.socket:close()
          return
        end
        local fm = Frame.ping():set_mask()
        local _, err = send_utils.send_all(self.socket, fm:encode())
        if not err then
          --log.debug(string.format("SENT FRAME: \n%s\n\n", utils.table_string(fm, nil, true)))
          pending_pongs = pending_pongs + 1
        elseif self.error_cb then
          self.error_cb(string.format("failed to send ping: "..err))
          self.socket:close()
          return
        end
      end
      goto continue
    end
    if recv[1] == self.socket then
      local frame, err = Frame.from_stream(self.socket)
      if not frame then
        if self._close_frame_sent then
          -- TODO this error case is a little weird, I think it happens if the server doesn't close properly
          if self.error_cb then self.error_cb("Failed to receive frame after sending close frame") end
          self.socket:close()
          return
        elseif err == "invalid opcode" or err == "invalid rsv bit" then
          log.trace("PROTOCOL ERR: received frame with " .. err)
          self:close(CloseCode.protocol(), err)
        elseif err == "timeout" and self.error_cb then
          -- TODO retry receiving the frame, give partially received frame to err_cb
          self.error_cb("failed to get frame from socket: " .. err)
        elseif err and err:match("close") then
          if self.error_cb then self.error_cb(err) end
          return
        elseif self.error_cb then
          self.error_cb("failed to get frame from socket: " .. err)
        end
        goto continue
      end
      --log.debug(string.format("RECEIVED FRAME: \n%s\n\n", utils.table_string(frame, nil, true)))
      if frame:is_control() then
        if not frame:is_final() then
          log.trace("PROTOCOL ERR: received non final control frame")
          self:close(CloseCode.protocol())
          goto continue
        end
        local control_type = frame.header.opcode.sub
        if frame:payload_len() > Frame.MAX_CONTROL_FRAME_LENGTH then
          log.trace("PROTOCOL ERR: received control frame that is too big")
          self:close(CloseCode.protocol())
          goto continue
        end
        if control_type == "ping" then
          local fm = Frame.pong(frame.payload):set_mask()
          local sent_bytes, err = send_utils.send_all(self.socket, fm:encode())
          if not sent_bytes and self.error_cb then
            self.error_cb("failed to send pong in response to ping: "..err)
          else
            log.trace(string.format("SENT FRAME: \n%s\n\n", utils.table_string(fm, nil, true)))
          end
        elseif control_type == "pong" then
          pending_pongs = 0 -- TODO this functionality is not tested by the test framework
          frames_since_last_ping = 0
        elseif control_type == "close" then
          self._close_frame_received = true
          if not self._close_frame_sent then
            self:close(CloseCode.decode(frame.payload))
          else
            log.trace("server copmleted our close handshake")
            self.socket:close()
            return
          end
        end
        goto continue
      end

      -- Should we close because we have been waiting to long for a ping?
      -- We might not need to do this, because it wasn't prioritized
      -- with a test case in autobahn
      if pending_pongs > 0 then
        frames_since_last_ping = frames_since_last_ping + 1
        if frames_since_last_ping > self.config._max_frames_without_pong then
          frames_since_last_ping = 0
          log.trace("PROTOCOL ERR: received too many frames while waiting for pong")
          self:close(CloseCode.policy(), "no pong after ping")
        end
      end

      -- handle fragmentation
      if frame.header.opcode.sub == "text" then
        msg_type = "text"
        if multiframe_message then -- we expected a continuation message
          self:close(CloseCode.protocol(), "expected " .. msg_type .. "continuation frame")
          goto continue
        end
        if not frame:is_final() then multiframe_message = true end
      elseif frame.header.opcode.sub == "binary" then
        msg_type = "binary"
        if multiframe_message then
          self:close(CloseCode.protocol(), "expected " .. msg_type .. "continuation frame")
          goto continue
        end
        if not frame:is_final() then multiframe_message = true end
      elseif frame.header.opcode.sub == "continue" and not multiframe_message then
        self:close(CloseCode.protocol(), "unexpected continue frame")
        goto continue
      end
      -- aggregate payloads
      if not frame:is_final() then
        received_bytes = received_bytes + frame:payload_len()
        -- TODO what should happen if we get message that is too big for the library?
        -- We are currently truncating the message.
        if received_bytes <= self.config.max_message_size then
          table.insert(partial_frames, frame.payload)
        else
          log.warn("truncating message thats bigger than max config size")
        end
        goto continue
      else
        multiframe_message = false
      end

      -- coalesce frame payloads into single message payload
      local full_payload = frame.payload
      if next(partial_frames) then
        table.insert(partial_frames, frame.payload)
        full_payload = table.concat(partial_frames)
        partial_frames = {}
      end
      if self.message_cb then self.message_cb(Message.new(msg_type, full_payload)) end
    elseif recv[1] == self._rx then -- frames we need to send on the socket
      local frame, err = self._rx:receive()
      if not frame then
        if self.error_cb then self.error_cb("channel receive failure: " .. err) end
        goto continue
      end

      local sent_bytes, err = send_utils.send_all(self.socket, frame:encode())
      if not sent_bytes then
        if self.error_cb then self.error_cb("socket send failure: " .. err) end
        goto continue
      end
      --log.debug(string.format("SENT FRAME: \n%s\n\n", utils.table_string(frame, nil, true)))

      if frame:is_control() and frame.header.opcode.sub == "close" then
        self._close_frame_sent = true
        if self.close_cb then self.close_cb("Close frame sent to server") end
        if self._close_frame_received then
          self.socket:close()
          log.trace("completed server close handshake")
          return
        end
      end
    end

    ::continue::
  end
end

return WebSocket
