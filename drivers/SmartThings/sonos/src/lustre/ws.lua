local cosock = require"cosock"
local socket = require"cosock.socket"
local Request = require"luncheon.request"
local Response = require"luncheon.response"
local send_utils = require"luncheon.utils"
local Handshake = require"lustre.handshake"
local Key = require"lustre.handshake.key"
local Config = require"lustre.config"
local Frame = require"lustre.frame"
local FrameHeader =
  require"lustre.frame.frame_header"
local OpCode = require"lustre.frame.opcode"
local CloseCode =
  require"lustre.frame.close".CloseCode
local Message = require"lustre.message"
local log = require"quietlog"

local utils = require"lustre.utils"

---@class WebSocket
---
---@field public id number|string
---@field public url string the endpoint to hit
---@field public socket table lua socket
---@field public handshake_key string key used in the websocket handshake
---@field public config Config
---@field private handshake Handshake
---@field private _send_tx table
---@field private _send_rx table
---@field private _recv_tx table
---@field private _recv_rx table
---@field private is_client boolean
local WebSocket = {}
WebSocket.__index = WebSocket

---Create new client object
---@param socket table connected tcp socket
---@param url string url to connect
---@param config Config
---@return WebSocket
---@return string|nil
function WebSocket.client(socket, url, config)
  local _send_tx, _send_rx = cosock.channel.new()
  local _recv_tx, _recv_rx = cosock.channel.new()
  local config = config or Config.default()
  local ret = setmetatable(
    {
      is_client = true,
      socket = socket,
      url = url or "/",
      handshake = Handshake.client(nil, config._protocols, config._extensions, config._extra_headers),
      config = config,
      _send_tx = _send_tx,
      _send_rx = _send_rx,
      _recv_tx = _recv_tx,
      _recv_rx = _recv_rx,
      id = math.random(),
      state = "Active",
    }, WebSocket)
  return ret
end

---Create a server side websocket (NOT YET IMPLEMENTED)
---@param socket table the cosock.tcp socket to use
---@param config Config The websocket configuration
---@return WebSocket
---@return string|nil @If an error occurs, returns the error message
function WebSocket.server(socket, config)
  return nil, "Not yet implemented"
end

---Receive the next message from this websocket
---@return Message
---@return string|nil
function WebSocket:receive()
  log.trace("WebSocket:receive")
  self._waker = nil
  local result = self._recv_rx:receive()
  if result.err then
    return nil, result.err
  end
  return result.msg
end

---@param text string
---@return number, string|nil
function WebSocket:send_text(text)
  if self.state ~= "Active" then
    return nil, "closed"
  end
  local valid_utf8, utf8_err =
    utils.validate_utf8(text)
  if not valid_utf8 then
    return nil, utf8_err
  end
  return self:send(Message.new("text", text))
end

---@param bytes string
---@return number
---@return number, string|nil
function WebSocket:send_bytes(bytes)
  return self:send(Message.new("binary", bytes))
end

-- TODO remove the fragmentation code duplication in the `send_text` and `send_bytes` apis
-- TODO  Could perhaps remove those apis entirely.
---@param message Message
---@return number, string|nil
function WebSocket:send(message)
  log.trace("WebSocket:send", message.type)
  local data_idx = 1
  local frames_sent = 0
  if self.state ~= "Active" then
    return nil, "closed"
  end
  local opcode
  if message.type == "text" then
    opcode = OpCode.text()
  else
    opcode = OpCode.binary()
  end
  repeat
    log.trace("send fragment top")
    local header = FrameHeader.default()
    local payload = ""
    if (message.data:len() - data_idx + 1)
      > self.config._max_frame_size then
      header:set_fin(false)
    end
    payload = string.sub(message.data, data_idx,
      data_idx + self.config._max_frame_size)
    if data_idx ~= 1 then
      header:set_opcode(OpCode.continue())
    else
      header:set_opcode(opcode)
    end
    header:set_length(#payload)
    local frame =
      Frame.from_parts(header, payload)
    frame:set_mask() -- todo handle client vs server
    local tx, rx = cosock.channel.new()
    local suc, err = self._send_tx:send(
      {frame = frame, reply = tx})
    if err then
      log.error("channel send error:", err)
    end
    local result = rx:receive()
    if result.err then
      return nil, result.err
    end
    data_idx = data_idx + frame:payload_len()
    frames_sent = frames_sent + 1
  until message.data:len() <= data_idx
  return 1
end

---@return number, string|nil
function WebSocket:client_handshake_and_start(host, port)
  if not self.is_client then -- todo use metatables to enforce this
    log.error(self.id, "Invalid client websocket")
    return nil, "only a client can connect"
  end
  -- Do handshake
  log.debug(self.id, "sending handshake")
  local success, err = self.handshake:send(
    self.socket, self.url,
    string.format("%s:%d", host, port))
  log.debug(self.id, "handshake complete",
    success or err)
  if not success then
    return nil, "invalid handshake: " .. err
  end
  cosock.spawn(function()
    self:_receive_loop()
  end, "Client receive loop")
  return 1
end

---@return number, string|nil
function WebSocket:connect(host, port)
  log.trace(self.id, "WebSocket:connect", host,
    port)
  if not self.is_client then -- todo use metatables to enforce this
    log.error(self.id, "Invalid client websocket")
    return nil, "only a client can connect"
  end
  if not host or not port then
    return nil, "missing host or port"
  end
  log.debug(self.id, "calling socket.connect")
  local r, err = self.socket:connect(host, port)
  log.debug(self.id, "Socket connect completed",
    r or err)
  if not r then
    return nil, "socket connect failure: " .. err
  end

  return self:client_handshake_and_start(host, port)
end

function WebSocket:accept()
  return nil, "Not yet implemented"
end

---@param close_code CloseCode
---@param reason string
---@return number 1 if success
---@return string|nil
function WebSocket:close(close_code, reason)
  log.debug("sending close message",
    close_code.type or close_code.value, reason)
  if self.state == "Active" then
    local close_frame = Frame.close(close_code,
      reason):set_mask() -- TODO client vs server
    local tx, reply = cosock.channel.new()
    reply:settimeout(0.5)
    log.debug("sending frame to socket task")
    local suc, err = self._send_tx:send(
      {frame = close_frame, reply = tx})
    log.debug("sent frame to socket task", suc,
      err)
    if not suc then
      return nil, "channel error:" .. err
    end
    log.debug("waiting on reply")
    local reply = reply:receive()
    log.debug("reply received")
    return reply
  elseif self.state == "ClosedBySelf" then
    self.state = "CloseAcknowledged"
  end

  return 1, log.debug("closed websocket")
end

---Cosock internal interface for using `cosock.socket.select`
---@param kind string
---@param waker fun()
function WebSocket:setwaker(kind, waker)
  assert(kind == "recvr",
    "unsupported wake kind: " .. tostring(kind))
  assert(self._waker == nil or waker == nil,
    "waker already set, receive can't be waited on from multiple places at once")
  self._waker = waker

  -- if messages waiting, immediately wake
  if #self._recv_tx.link.queue > 0 and waker then
    waker()
  end
end

---Spawn the receive loop
---@return string|nil
function WebSocket:_receive_loop()
  log.trace(self.id, "starting receive loop")
  local loop_state = {
    partial_frames = nil,
    received_bytes = 0,
    frames_since_last_ping = 0,
    pending_pongs = 0,
    multiframe_message = false,
    utf8_check_backward_idx = 0,
    msg_type = nil,
  }
  local order = false
  while self.state ~= "CloseAcknowledged"
    and self.state ~= "Terminated" do
    log.trace(self.id, "loop top")
    local rs = (order
                 and {self._send_rx, self.socket})
                 or {self.socket, self._send_rx}
    order = not order
    local recv, _, err = socket.select(rs, nil,
      self.config._keep_alive)
    log.debug((recv and "recv") or "~recv",
      err or "")
    if not recv then
      if self:_handle_select_err(loop_state, err) then
        return
      end
    end
    if self:_handle_recvs(loop_state, recv, 1) then
      break
    end
  end
  log.debug("Closing socket")
  self.socket:close()
  log.debug("Closing channel")
  self._send_rx:close()
  log.debug("Channel closed")
end

function WebSocket:_handle_recvs(state, recv, idx)
  log.trace(self.id, "_handle_recvs")
  if recv[idx] == self.socket then
    return self:_handle_recv_ready(state) and 1
  end
  if recv[idx] == self._send_rx then -- frames we need to send on the socket
    return self:_handle_send_ready()
  end
end

function WebSocket:_handle_select_err(state, err)
  log.debug(self.id, "selected err:", err)
  if err == "timeout" then
    if state.pending_pongs >= 2 then -- TODO max number of pings without a pong could be configurable
      self._recv_tx:send({
        err = "no response to ping",
      })
      self.state = "Terminated"
      log.debug("Closing socket")
      self.socket:close()
      return 1
    end
    local fm = Frame.ping():set_mask()
    local sent_bytes, err =
      send_utils.send_all(self.socket, fm:encode())
    if not err then
      log.debug(self.id, "SENT FRAME: \n%s\n\n")
      state.pending_pongs =
        state.pending_pongs + 1
    else
      self._recv_rx:send({err = err})
      self.state = "Terminated"
      log.debug("Closing socket")
      self.socket:close()
      return 1
    end
  end
end

function WebSocket:_handle_recv_ready(state)
  log.debug(self.id, "selected socket")
  local frame, err =
    Frame.from_stream(self.socket)
  log.debug(self.id, "build frame", frame or err)
  if not frame then
    log.info("error building frame", err)
    if err == "invalid opcode" or err
      == "invalid rsv bit" then
      log.warn(self.id,
        "PROTOCOL ERR: received frame with " .. err)
      self._send_tx:send({
        frame = Frame.close(CloseCode.protocol()),
      })
    elseif err == "timeout" then
      -- TODO retry receiving the frame, give partially received frame
      self._recv_tx:send({err = err})
      if self._waker then
        self._waker()
      end
    elseif err == "closed" then
      log.debug("socket was closed", self.state)
      if self.state == "Active" or self.state
        == "ClosedBySelf" then
        self._recv_tx:send({err = err})
        if self._waker then
          self._waker()
        end
        self.state = "Terminated"
      end
      return 1
    else
      self._recv_tx:send({err = err})
      if self._waker then
        self._waker()
      end
    end
    return
  end
  log.debug(self.id,
    string.format("RECEIVED FRAME %s %s",
      frame.header.opcode.type,
      frame.header.opcode.sub))
  if frame:is_control() then
    return self:_handle_recv_control_frame(frame,
      state)
  end

  -- Should we close because we have been waiting to long for a ping?
  -- We might not need to do this, because it wasn't prioritized
  -- with a test case in autobahn
  if state.pending_pongs > 0 then
    state.frames_since_last_ping =
      state.frames_since_last_ping + 1
    if state.frames_since_last_ping
      > self.config._max_frames_without_pong then
      state.frames_since_last_ping = 0
      log.trace(self.id,
        "PROTOCOL ERR: received too many frames while waiting for pong")
      self._send_tx:send({
        frame = Frame.close(CloseCode.policy(),
          "no pong after ping"),
      })
      return
    end
  end

  -- handle fragmentation
  if state.multiframe_message then
    if frame.header.opcode.sub ~= "continue" then
      log.warn("Expected continue frame found ",
        frame.header.opcode.sub)
      self._send_tx:send({
        frame = Frame.close(CloseCode.protocol(),
          "unexpected continue frame"),
      })
      return
    end
    if state.msg_type == "text" then
      if self:_handle_recv_text_frame(frame, state) then
        return
      end
    end
  elseif frame.header.opcode.sub == "continue" then
    log.warn("Unexpected continue frame")
    self._send_tx:send({
      frame = Frame.close(CloseCode.protocol(),
        "unexpected continue frame"),
    })
    return
  else
    if frame.header.opcode.sub == "text" then
      if self:_handle_recv_text_frame(frame, state) then
        return
      end
    end
    state.msg_type = frame.header.opcode.sub
    state.multiframe_message =
      not frame:is_final()
  end
  -- aggregate payloads
  if not frame:is_final() then
    state.received_bytes =
      state.received_bytes + frame:payload_len()
    -- TODO what should happen if we get message that is too big for the library?
    -- We are currently truncating the message.
    if state.received_bytes
      <= self.config.max_message_size then
      state.partial_frames =
        (state.partial_frames or "")
          .. frame.payload
    else
      log.warn(self.id,
        "truncating message thats bigger than max config size")
    end
    return
  else
    state.multiframe_message = false
  end

  -- coalesce frame payloads into single message payload
  local full_payload = frame.payload
  if state.partial_frames then
    full_payload = state.partial_frames
                     .. frame.payload
    state.partial_frames = nil
  end
  if state.msg_type == "text" then
    log.debug("checking for valid utf8")
    local valid_utf8, utf8_err =
      utils.validate_utf8(full_payload)
    log.trace("valid?", not not valid_utf8,
      utf8_err)
    if not valid_utf8 then
      log.warn(
        "Received invalid utf8 text message, closing",
        utf8_err)
      send_utils.send_all(self.socket,
        Frame.close(CloseCode.protocol(), utf8_err):encode())
      self.socket:close()
      self.state = "Terminated"
      self._recv_tx:send({err = "closed"})
      if self._waker then
        self._waker()
      end
      return
    end
  end
  self._recv_tx:send({
    msg = Message.new(state.msg_type, full_payload),
  })
  if self._waker then
    self._waker()
  end
end

---
---@param frame Frame
---@param state table
function WebSocket:_handle_recv_text_frame(frame,
  state)
  log.debug("checking for valid utf8")
  local valid_utf8, utf8_err, err_idx =
    utils.validate_utf8((state.partial_utf8_bytes
                          or "") .. frame.payload)
  log.trace("valid?", not not valid_utf8,
    utf8_err, err_idx)
  if not valid_utf8 then
    if utf8_err == "Invalid UTF-8 too short" then
      state.partial_utf8_bytes =
        ((state.partial_frames or "")
          .. frame.payload):sub(err_idx)
      log.debug(
        "utf8 too short updated partial_utf8_bytes",
        state.partial_utf8_bytes)
      if not frame:is_final() then
        return
      end
    else
      state.partial_utf8_bytes = ""
    end

    log.warn(
      "Received invalid utf8 text frame, closing",
      utf8_err)
    self._send_tx:send({
      frame = Frame.close(CloseCode.protocol(),
        utf8_err),
    })
    self._recv_tx:send({err = "closed"})
    self.state = "Terminated"
    self.socket:close()
    return
  else
    state.partial_utf8_bytes = ""
  end
end

function WebSocket:_handle_recv_control_frame(
  frame, state)
  if not frame:is_final() then
    log.trace(self.id,
      "PROTOCOL ERR: received non final control frame")
    self._send_tx:send({
      frame = Frame.close(CloseCode.protocol()),
    })
    return
  end
  local control_type = frame.header.opcode.sub
  if frame:payload_len()
    > Frame.MAX_CONTROL_FRAME_LENGTH then
    log.trace(self.id,
      "PROTOCOL ERR: received control frame that is too big")
    self._send_tx:send({
      frame = Frame.close(CloseCode.protocol()),
    })
    return
  end
  if control_type == "ping" then
    local fm =
      Frame.pong(frame.payload):set_mask()
    local sent_bytes, err =
      send_utils.send_all(self.socket, fm:encode())
    if not sent_bytes then
      self._recv_tx:send({
        err = "failed to send pong in response to ping: "
          .. err,
      })
    end
    return
  elseif control_type == "pong" then
    state.pending_pongs =
      math.max(state.pending_pongs - 1, 0) -- TODO this functionality is not tested by the test framework
    state.frames_since_last_ping = 0
  elseif control_type == "close" then
    self._send_tx:send({
      frame = Frame.close(
        CloseCode.decode(frame.payload)),
    })
  end
end

function WebSocket:_handle_send_ready()
  log.debug(self.id, "selected channel")
  local event, err = self._send_rx:receive()
  log.debug("received from rx")
  if not event then
    log.error(
      "error receiving event from _send_rx", err)
    return
  end
  ---@type Frame, cosock.channel
  local frame, reply = event.frame, event.reply
  log.debug("encoding frame: ",
    frame.header.opcode.type,
    frame.header.opcode.sub)
  local bytes = frame:encode()
  log.debug("sending all bytes")
  local sent_bytes, err =
    send_utils.send_all(self.socket, bytes)
  log.debug("sent bytes")
  if not sent_bytes then
    local closed = err:match("close")
    if closed and self.state == "Active" then
      log.debug("closed error", err)
      if reply and reply.send then
        reply:send({err = err})
      else
        log.error("No reply channel in event for progating error")
      end
    end
    if not closed then
      if reply and reply.send then
        reply:send({err = err})
      else
        log.error("No reply channel in event for progating error")
      end
    end
    return
  end
  log.debug(self.id, "SENT FRAME")
  local ret

  if frame:is_close() then
    return self:_handle_sent_close_frame()
  end
  if reply then
    reply:send({ok = 1})
  end
end

function WebSocket:_handle_sent_close_frame()
  if self.state == "Active" then
    self.state = "ClosedBySelf"
  end
  if self.state == "ClosedByPeer" then
    self.state = "CloseAcknowledged"
    self.socket:close()
    if self._waker then
      self._waker()
    end
    return 1
  end
end

function WebSocket:_handle_recvd_close_frame()
  if self.state == "Active" then
    self.state = "ClosedByPeer"
  end
  if self.state == "ClosedBySelf" then
    self.state = "CloseAcknowledged"
    self.socket:close()
    self._recv_tx:send({err = "closed"})
    if self._waker then
      self._waker()
    end
    return 1
  end
end

return WebSocket
