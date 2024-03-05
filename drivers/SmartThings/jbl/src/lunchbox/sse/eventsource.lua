local cosock = require "cosock"
local socket = require "cosock.socket"
local ssl = require "cosock.ssl"

local log = require "log"
local util = require "lunchbox.util"
local Request = require "luncheon.request"
local Response = require "luncheon.response"

--- A pure Lua implementation of the EventSource interface.
--- The EventSource interface represents the client end of an HTTP(S)
--- connection that receives an event stream following the Server-Sent events
--- specification.
---
--- MDN Documentation for EventSource: https://developer.mozilla.org/en-US/docs/Web/API/EventSource
--- HTML Spec: https://html.spec.whatwg.org/multipage/server-sent-events.html
---
--- @class EventSource
--- @field public url table A `net.url` table representing the URL for the connection
--- @field public ready_state number Enumeration of the ready states outlined in the spec.
--- @field public onopen function in-line callback for on-open events
--- @field public onmessage function in-line callback for on-message events
--- @field public onerror function in-line callback for on-error events; error callbacks will fire
--- @field package _reconnect boolean flag that says whether or not the client should attempt to reconnect on close.
--- @field package _reconnect_time_millis number The amount of time to wait between reconnects, in millis. Can be sent by the server.
--- @field package _sock_builder function|nil optional. If this function exists, it will be called to create a new TCP socket on connection.
--- @field package _sock table? the TCP socket for the connection
--- @field package _needs_more boolean flag to track whether or not we're still expecting mroe on this source before we dispatch
--- @field package _last_field string the last field the parsing path saw, in case it needs to append more to its value
--- @field package _extra_headers table a table of string:string key-value pairs that will be inserted in to the initial requests's headers.
--- @field package _parse_buffers table inner state, keeps track of the various event stream buffers in between dispatches.
--- @field package _listeners table event listeners attached using the add_event_listener API instead of the inline callbacks.
local EventSource = {}
EventSource.__index = EventSource

--- The Ready States that an EventSource can be in. We use base 0 to match the specification.
EventSource.ReadyStates = util.read_only {
  CONNECTING = 0, -- The connection has not yet been established
  OPEN = 1,       -- The connection is open
  CLOSED = 2      -- The connection has closed
}

--- The event types supported by this source, patterned after their values in JavaScript.
EventSource.EventTypes = util.read_only {
  ON_OPEN = "open",
  ON_MESSAGE = "message",
  ON_ERROR = "error",
}

--- Helper function that creates the initial Request to start the stream.
--- @function create_request
--- @local
--- @param url_table table a net.url table
--- @param extra_headers table a set of key/value pairs (strings) to capture any extra HTTP headers needed.
local function create_request(url_table, extra_headers)
  local request = Request.new("GET", url_table.path, nil)
      :add_header("user-agent", "smartthings-lua-edge-driver")
      :add_header("host", string.format("%s", url_table.host))
      :add_header("connection", "keep-alive")
      :add_header("accept", "text/event-stream")

  if type(extra_headers) == "table" then
    for k, v in pairs(extra_headers) do
      request = request:add_header(k, v)
    end
  end

  return request
end

--- Helper function to send the request and kick off the stream.
--- @function send_stream_start_request
--- @local
--- @param payload string the entire string buffer to send
--- @param sock table the TCP socket to send it over
local function send_stream_start_request(payload, sock)
  local bytes, err, idx = nil, nil, 0

  repeat
    bytes, err, idx = sock:send(payload, idx + 1, #payload)
  until (bytes == #payload) or (err ~= nil)

  if err then
    log.error_with({ hub_logs = true }, "send error: " .. err)
  end

  return bytes, err, idx
end

--- Helper function to create an table representing an event from the source's parse buffers.
--- @function make_event
--- @local
--- @param source EventSource
local function make_event(source)
  local event_type = nil

  if #source._parse_buffers["event"] > 0 then
    event_type = source._parse_buffers["event"]
  end

  return {
    type = event_type or "message",
    data = source._parse_buffers["data"],
    origin = source.url.scheme .. "://" .. source.url.host,
    lastEventId = source._parse_buffers["id"]
  }
end

--- SSE spec for dispatching an event:
--- https://html.spec.whatwg.org/multipage/server-sent-events.html#dispatchMessage
--- @function dispatch_event
--- @local
--- @param source EventSource
local function dispatch_event(source)
  local data_buffer = source._parse_buffers["data"]
  local is_blank_line = data_buffer ~= nil and
      (#data_buffer == 0) or
      data_buffer == "\n" or
      data_buffer == "\r" or
      data_buffer == "\r\n"
  if data_buffer ~= nil and not is_blank_line then
    local event = util.read_only(make_event(source))

    if type(source.onmessage) == "function" then
      source.onmessage(event)
    end

    for _, listener in ipairs(source._listeners[EventSource.EventTypes.ON_MESSAGE]) do
      if type(listener) == "function" then
        listener(event)
      end
    end
  end

  source._parse_buffers["event"] = ""
  source._parse_buffers["data"] = ""
end

local valid_fields = util.read_only {
  ["event"] = true,
  ["data"] = true,
  ["id"] = true,
  ["retry"] = true
}

-- An event stream "line" can end in more than one way; from the spec:
-- Lines must be separated by either
-- a U+000D CARRIAGE RETURN U+000A LINE FEED (CRLF) character pair,
-- a single U+000A LINE FEED (LF) character,
-- or a single U+000D CARRIAGE RETURN (CR) character.
--
-- util.iter_string_lines won't suffice here because:
-- a.) it assumes \n, and
-- b.) it doesn't differentiate between a "line" that ends without a newline and one that does.
--
-- h/t to github.com/FreeMasen for the suggestions on the efficient implementation of this
local function find_line_endings(chunk)
  local r_idx, n_idx = string.find(chunk, "[\r\n]+")
  if r_idx == nil or r_idx == n_idx then
    -- 1 character or no match
    return r_idx, n_idx
  end
  local slice = string.sub(chunk, r_idx, n_idx)
  if slice == "\r\n" then
    return r_idx, n_idx
  end
  -- invalid multi character match, return first character only
  return r_idx, r_idx
end

local function event_lines(chunk)
  local remaining = chunk
  local line_end, rn_end
  local remainder_sent = false
  return function()
    line_end, rn_end = find_line_endings(remaining)
    if not line_end then
      if remainder_sent or (not remaining) or #remaining == 0 then
        return nil
      else
        remainder_sent = true
        return remaining, false
      end
    end
    local next_line = string.sub(remaining, 1, line_end - 1)
    remaining = string.sub(remaining, rn_end + 1)
    return next_line, true
  end
end
--- SSE spec for interpreting an event stream:
--- https://html.spec.whatwg.org/multipage/server-sent-events.html#the-eventsource-interface
--- @function parse
--- @local
--- @param source EventSource
--- @param recv string the received payload from the last socket receive
local function sse_parse_chunk(source, recv)
  for line, complete in event_lines(recv) do
    if not source._needs_more and (#line == 0 or (not line:match("([%w%p]+)"))) then -- empty/blank lines indicate dispatch
      dispatch_event(source)
    elseif source._needs_more then
      local append = line
      if source._last_field == "data" and complete then append = append .. "\n" end
      if complete then source._needs_more = false end
      source._parse_buffers[source._last_field] = source._parse_buffers[source._last_field] .. append
    else
      if line:sub(1, 1) ~= ":" then                  -- ignore any complete lines that start w/ a colon
        local matches = line:gmatch("(%w*)(:*)(.*)") -- colon after field is optional, in that case it's a field w/ no value

        for field, _colon, value in matches do
          value = value:gsub("^[^%g]", "", 1) -- trim a single leading space character

          if valid_fields[field] then
            source._last_field = field
            if field == "retry" then
              local new_time = tonumber(value, 10)
              if type(new_time) == "number" then
                source._reconnect_time_millis = new_time
              end
            elseif field == "data" then
              local append = (value or "")
              if complete then append = append .. "\n" end
              source._parse_buffers[field] = source._parse_buffers[field] .. append
            elseif field == "id" then
              -- skip ID's if they contain the NULL character
              if not string.find(value, '\0') then
                source._parse_buffers[field] = value
              end
            else
              source._parse_buffers[field] = value
            end
          end
          source._needs_more = source._needs_more or (not complete)
        end
      end
    end
  end
end

--- Helper function that captures the cyclic logic of the EventSource while in the CONNECTING state.
--- @function connecting_action
--- @local
--- @param source EventSource
local function connecting_action(source)
  if not source._sock then
    if type(source._sock_builder) == "function" then
      source._sock = source._sock_builder()
    else
      source._sock, err = socket.tcp()
      if err ~= nil then return nil, err end

      _, err = source._sock:settimeout(60)
      if err ~= nil then return nil, err end

      _, err = source._sock:connect(source.url.host, source.url.port)
      if err ~= nil then return nil, err end

      _, err = source._sock:setoption("keepalive", true)
      if err ~= nil then return nil, err end

      if source.url.scheme == "https" then
        source._sock, err = ssl.wrap(source._sock, {
          mode = "client",
          protocol = "any",
          verify = "none",
          options = "all"
        })
        if err ~= nil then return nil, err end

        _, err = source._sock:dohandshake()
        if err ~= nil then return nil, err end
      end
    end
  end

  local request = create_request(source.url, source._extra_headers)

  local last_event_id = source._parse_buffers["id"]

  if last_event_id ~= nil and #last_event_id > 0 then
    request = request:add_header("Last-Event-ID", last_event_id)
  end

  local _, err, _ = send_stream_start_request(request:serialize(), source._sock)

  if err ~= nil then
    return nil, err
  end

  local response
  response, err = Response.tcp_source(source._sock)

  if not response or err ~= nil then
    return nil, err or "nil response from Response.tcp_source"
  end

  if response.status ~= 200 then
    return nil, "Server responded with status other than 200 OK", { response.status, response.status_msg }
  end

  local headers, err = response:get_headers()
  if err ~= nil then
    return nil, err
  end
  local content_type = string.lower((headers and headers:get_one('content-type') or "none"))
  if not content_type:find("text/event-stream", 1, true) then
    local err_msg = "Expected content type of text/event-stream in response headers, received: " .. content_type
    return nil, err_msg
  end

  source.ready_state = EventSource.ReadyStates.OPEN

  if type(source.onopen) == "function" then
    source.onopen()
  end

  for _, listener in ipairs(source._listeners[EventSource.EventTypes.ON_OPEN]) do
    if type(listener) == "function" then
      listener()
    end
  end
end
--- Helper function that captures the cyclic logic of the EventSource while in the OPEN state.
--- @function open_action
--- @local
--- @param source EventSource
local function open_action(source)
  local recv, err, partial = source._sock:receive('*l')

  if err then
    --- connection is fine but there was nothing
    --- to be read from the other end so we just
    --- early return.
    if err == "timeout" or err == "wantread" then
      return
    else
      --- real error, close the connection.
      source._sock:close()
      source._sock = nil
      source.ready_state = EventSource.ReadyStates.CLOSED
      return nil, err, partial
    end
  end

  -- the number of bytes to read per the chunked encoding spec
  local recv_as_num = tonumber(recv, 16)

  if recv_as_num ~= nil then
    recv, err, partial = source._sock:receive(recv_as_num)
    if err then
      if err == "timeout" or err == "wantread" then
        return
      else
        --- real error, close the connection.
        source._sock:close()
        source._sock = nil
        source.ready_state = EventSource.ReadyStates.CLOSED
        return nil, err, partial
      end
    end
    local _, err, partial = source._sock:receive('*l') -- clear the final line

    if err then
      if err == "timeout" or err == "wantread" then
        return
      else
        --- real error, close the connection.
        source._sock:close()
        source._sock = nil
        source.ready_state = EventSource.ReadyStates.CLOSED
        return nil, err, partial
      end
    end
    sse_parse_chunk(source, recv)
  else
    local recv_dbg = recv or "<NIL>"
    if #recv_dbg == 0 then recv_dbg = "<EMPTY>" end
    recv_dbg = recv_dbg:gsub("\r\n", "<CRLF>"):gsub("\n", "<LF>"):gsub("\r", "<CR>")
    log.error_with({ hub_logs = true },
      string.format("Received %s while expecting a chunked encoding payload length (hex number)\n", recv_dbg))
  end
end

--- Helper function that captures the cyclic logic of the EventSource while in the CLOSED state.
--- @function closed_action
--- @local
--- @param source EventSource
local function closed_action(source)
  if source._sock ~= nil then
    source._sock:close()
    source._sock = nil
  end

  if source._reconnect then
    if type(source.onerror) == "function" then
      source.onerror()
    end

    for _, listener in ipairs(source._listeners[EventSource.EventTypes.ON_ERROR]) do
      if type(listener) == "function" then
        listener()
      end
    end

    local sleep_time_secs = source._reconnect_time_millis / 1000.0
    socket.sleep(sleep_time_secs)

    source.ready_state = EventSource.ReadyStates.CONNECTING
  end
end

local state_actions = {
  [EventSource.ReadyStates.CONNECTING] = connecting_action,
  [EventSource.ReadyStates.OPEN] = open_action,
  [EventSource.ReadyStates.CLOSED] = closed_action
}

--- Create a new EventSource. The only required parameter is the URL, which can
--- be a string or a net.url table. The string form will be converted to a net.url table.
---
--- @param url string|table a string or a net.url table representing the complete URL (minimally a scheme/host/path, port optional) for the event stream.
--- @param extra_headers table|nil an optional table of key-value pairs (strings) to be added to the initial GET request
--- @param sock_builder function|nil an optional function to be used to create the TCP socket for the stream. If nil, a set of defaults will be used to create a new TCP socket.
--- @return EventSource a new EventSource
function EventSource.new(url, extra_headers, sock_builder)
  local url_table = util.force_url_table(url)

  if not url_table.port then
    if url_table.scheme == "http" then
      url_table.port = 80
    elseif url_table.scheme == "https" then
      url_table.port = 443
    end
  end

  local sock = nil

  if type(sock_builder) == "function" then
    sock = sock_builder()
  end

  local source = setmetatable({
    url = url_table,
    ready_state = EventSource.ReadyStates.CONNECTING,
    onopen = nil,
    onmessage = nil,
    onerror = nil,
    _needs_more = false,
    _last_field = nil,
    _reconnect = true,
    _reconnect_time_millis = 1000,
    _sock_builder = sock_builder,
    _sock = sock,
    _extra_headers = extra_headers,
    _parse_buffers = {
      ["data"] = "",
      ["id"] = "",
      ["event"] = "",
    },
    _listeners = {
      [EventSource.EventTypes.ON_OPEN] = {},
      [EventSource.EventTypes.ON_MESSAGE] = {},
      [EventSource.EventTypes.ON_ERROR] = {}
    },
  }, EventSource)

  cosock.spawn(function()
    local st_utils = require "st.utils"
    while true do
      if source.ready_state == EventSource.ReadyStates.CLOSED and
          not source._reconnect
      then
        return
      end
      local _, action_err, partial = state_actions[source.ready_state](source)
      if action_err ~= nil then
        if action_err ~= "timeout" or action_err ~= "wantread" then
          log.error_with({ hub_logs = true }, "Event Source Coroutine State Machine error: " .. action_err)
          if partial ~= nil and #partial > 0 then
            log.error_with({ hub_logs = true }, st_utils.stringify_table(partial, "\tReceived Partial", true))
          end
          source.ready_state = EventSource.ReadyStates.CLOSED
        end
      end
    end
  end)

  return source
end

--- Close the event source, signalling that a reconnect is not desired
function EventSource:close()
  self._reconnect = false
  if self._sock ~= nil then
    self._sock:close()
  end
  self._sock = nil
  self.ready_state = EventSource.ReadyStates.CLOSED
end

--- Add a callback to the event source
---@param listener_type string One of "message", "open", or "error"
---@param listener function the callback to be called in case of an event. Open and Error events have no payload. The message event will have a single argument, a table.
function EventSource:add_event_listener(listener_type, listener)
  local list = self._listeners[listener_type]

  if list then
    table.insert(list, listener)
  end
end

return EventSource
