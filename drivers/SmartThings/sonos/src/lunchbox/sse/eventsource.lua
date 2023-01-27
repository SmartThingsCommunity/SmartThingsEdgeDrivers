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
--- @field private _reconnect boolean flag that says whether or not the client should attempt to reconnect on close.
--- @field private _reconnect_time_millis number The amount of time to wait between reconnects, in millis. Can be sent by the server.
--- @field private _sock_builder function|nil optional. If this function exists, it will be called to create a new TCP socket on connection.
--- @field private _sock table the TCP socket for the connection
--- @field private _extra_headers table a table of string:string key-value pairs that will be inserted in to the initial requests's headers.
--- @field private _parse_buffers table inner state, keeps track of the various event stream buffers in between dispatches.
--- @field private _listeners table event listeners attached using the add_event_listener API instead of the inline callbacks.
local EventSource = {}
EventSource.__index = EventSource

--- The Ready States that an EventSource can be in. We use base 0 to match the specification.
EventSource.ReadyStates = util.read_only {
    CONNECTING = 0, -- The connection has not yet been established
    OPEN = 1, -- The connection is open
    CLOSED = 2 -- The connection has closed
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
        for k,v in pairs(extra_headers) do
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
        log.error("send error: " .. err)
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
    if #source._parse_buffers["data"] > 0 then
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
--- SSE spec for interpreting an event stream:
--- https://html.spec.whatwg.org/multipage/server-sent-events.html#the-eventsource-interface
--- @function parse
--- @local
--- @param source EventSource
--- @param recv string the received payload from the last socket receive
local function parse(source, recv)
    for line in util.iter_string_lines(recv) do
        if #line == 0 or (not line:match("([%w%p]+)")) then -- empty/blank lines indicate dispatch
            dispatch_event(source)
        else
            if line:sub(1,1) ~= ":" then -- ignore any lines that start w/ a colon
                local matches = line:gmatch("(%w*)(:*)(.*)") -- colon is optional, in that case it's a field w/ no value

                for field, _colon, value in matches do
                    field = field:gsub("^%s*(.-)%s*$", "%1") -- trim whitespace
                    value = value:gsub("^%s*(.-)%s*$", "%1") -- trim whitespace

                    if valid_fields[field] then
                        if field == "retry" then
                            source._reconnect_time_millis = tonumber(value, 10) or 1000
                        elseif field == "data" then
                            source._parse_buffers[field] = source._parse_buffers[field] .. (value or "")
                        else
                            source._parse_buffers[field] = value
                        end
                    end
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
            if not err then
                _, err = source._sock:connect(source.url.host, source.url.port)

                if not err then
                    source._sock:setoption("keepalive", true)

                    if source.url.scheme == "https" then
                        source._sock = ssl.wrap(source._sock, {
                            mode = "client",
                            protocol = "any",
                            verify = "none",
                            options = "all"
                        })

                        source._sock:dohandshake()
                    end
                else
                    log.warn("Event source error: " .. err)
                end
            else
                log.warn("Event source error: " .. err)
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

    local recv, partial = nil, nil
    recv, err, partial = Response.source(function() return source._sock:receive() end)

    if err ~= nil then
        log.error("start stream receive error" .. err)
        return nil, err, partial
    end

    if recv.status ~= 200 then
        return nil, "Server responded with status other than 200 OK", recv
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
        log.warn("Event source error: " .. err)
        source._sock:close()
        source._sock = nil
        source.ready_state = EventSource.ReadyStates.CLOSED
        return nil, err, partial
    end

    local recv_as_num = tonumber(recv, 16)

    if recv_as_num ~= nil then
        recv, err, partial = source._sock:receive(recv_as_num)
        _ = source._sock:receive('*l') -- clear trailing crlf

        parse(source, recv)
    end
end

--- Helper function that captures the cyclic logic of the EventSource while in the CLOSED state.
--- @function closed_action
--- @local
--- @param source EventSource
local function closed_action(source)
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
        if url_table.scheme == "http" then url_table.port = 80
        elseif url_table.scheme == "https" then url_table.port = 443
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
        while true do
            state_actions[source.ready_state](source)
            -- socket.sleep(1)
        end
    end)

    return source
end

--- Close the event source, signalling that a reconnect is not desired
function EventSource:close()
    self._reconnect = false
    self._sock:close()
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
