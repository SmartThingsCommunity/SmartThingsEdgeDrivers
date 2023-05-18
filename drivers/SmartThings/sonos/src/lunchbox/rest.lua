local socket = require "cosock.socket"
local ssl = require "cosock.ssl"
local log = require "log"

local utils = require "lunchbox.util"
local Request = require "luncheon.request"
local Response = require "luncheon.response"

local RestCallStates = {
  SEND = "Send",
  RECEIVE = "Receive",
  RETRY = "Retry",
  RECONNECT = "Reconnect",
  COMPLETE = "Complete",
}

-- build a exponential backoff time value generator
--
-- max: the maximum wait interval (not including `rand factor`)
-- inc: the rate at which to exponentially back off
-- rand: a randomization range of (-rand, rand) to be added to each interval
local function backoff_builder(max, inc, rand)
  local count = 0
  inc = inc or 1
  return function()
    local randval = 0
    if rand then
      randval = math.random() * rand * 2 - rand
    end

    local base = inc * (2 ^ count - 1)
    count = count + 1

    -- ensure base backoff (not including random factor) is less than max
    if max then base = math.min(base, max) end

    -- ensure total backoff is >= 0
    return math.max(base + randval, 0)
  end
end

local function connect(client)
  local port = 80
  local use_ssl = false

  if client.base_url.scheme == "https" then
    port = 443
    use_ssl = true
  end

  if client.base_url.port ~= port then port = client.base_url.port end

  client.socket = client.socket_builder(client.base_url.host, port, use_ssl)
end

local function reconnect(client)
  client.socket:close()
  client.socket = nil
  connect(client)
end

local function send_request(client, request)
  local payload = request:serialize()

  local bytes, err, idx = nil, nil, 0
  if client.socket == nil then return nil, "closed", nil end

  repeat bytes, err, idx = client.socket:send(payload, idx + 1, #payload) until (bytes == #payload)
      or (err ~= nil)

  return bytes, err, idx
end

local function parse_chunked_response(original_response, sock)
  local ChunkedTransferStates = {
    EXPECTING_CHUNK_LENGTH = "ExpectingChunkLength",
    EXPECTING_BODY_CHUNK = "ExpectingBodyChunk",
  }

  local full_response = Response.new(original_response.status, nil)

  for header in original_response.headers:iter() do full_response.headers:append_chunk(header) end

  local next_chunk_bytes = tonumber(original_response:get_body(), 16)
  local next_chunk_body = ""
  local bytes_read = 0;

  local state = ChunkedTransferStates.EXPECTING_BODY_CHUNK

  repeat
    local pat = nil
    local next_recv, next_err, partial = nil, nil, nil

    if state == ChunkedTransferStates.EXPECTING_BODY_CHUNK then
      pat = next_chunk_bytes
    else
      pat = "*l"
    end

    next_recv, next_err, partial = sock:receive(pat)

    if next_err ~= nil then
      if string.lower(next_err) == "closed" then
        if partial ~= nil and #partial >= 1 then
          full_response:append_body(partial)
          next_chunk_bytes = 0
        end
      else
        return nil, ("unexpected error reading chunked transfer: " .. next_err)
      end
    end

    if next_recv ~= nil and #next_recv >= 1 then
      if state == ChunkedTransferStates.EXPECTING_BODY_CHUNK then
        bytes_read = bytes_read + #next_recv
        next_chunk_body = next_chunk_body .. next_recv

        if bytes_read >= next_chunk_bytes then
          full_response = full_response:append_body(next_chunk_body)
          next_chunk_body = ""
          bytes_read = 0

          state = ChunkedTransferStates.EXPECTING_CHUNK_LENGTH
        end
      elseif state == ChunkedTransferStates.EXPECTING_CHUNK_LENGTH then
        next_chunk_bytes = tonumber(next_recv, 16)

        state = ChunkedTransferStates.EXPECTING_BODY_CHUNK
      end
    end
  until next_chunk_bytes == 0

  local _ = sock:receive("*l") -- clear the trailing CRLF

  full_response._received_body = true
  full_response._parsed_headers = true

  return full_response
end

local function handle_response(sock)
  -- called select right before passing in so we receive immediately
  local initial_recv, initial_err, partial = Response.source(function() return sock:receive('*l') end)

  local full_response = nil

  if initial_recv ~= nil then
    local headers = initial_recv:get_headers()

    if headers:get_one("Transfer-Encoding") == "chunked" then
      full_response = parse_chunked_response(initial_recv, sock)
    else
      if headers:get_one("Content-length") then
        body = sock:receive(tonumber(headers:get_one("Content-length")))
        initial_recv:append_body(body)
        initial_recv._received_body = true
      end
      full_response = initial_recv
    end

    return full_response
  else
    return nil, initial_err, partial
  end
end

local function execute_request(client, request, retry_fn)
  if client.socket == nil then connect(client) end

  local should_retry = retry_fn or function() return false end

  -- send output
  local _bytes_sent, send_err, _idx = nil, nil, 0
  -- recv output
  local response, recv_err, _partial = nil, nil, nil
  -- return values
  local ret, err = nil, nil

  local backoff = backoff_builder(60, 1, 0.1)
  local current_state = RestCallStates.SEND

  repeat
    if current_state == RestCallStates.SEND then

      _bytes_sent, send_err, _idx = send_request(client, request)

      if not send_err then
        current_state = RestCallStates.RECEIVE
      elseif should_retry() then
        if string.lower(send_err) == "closed" or string.lower(send_err):match("broken pipe") then
          current_state = RestCallStates.RECONNECT
        else
          current_state = RestCallStates.RETRY
        end
      else
        ret = nil
        err = send_err
        current_state = RestCallStates.COMPLETE
      end
    elseif current_state == RestCallStates.RECEIVE then
      response, recv_err, _partial = handle_response(client.socket)

      if not recv_err then
        ret = response
        err = nil
        current_state = RestCallStates.COMPLETE
      elseif should_retry() then
        if string.lower(recv_err) == "closed" or string.lower(recv_err):match("broken pipe") then
          current_state = RestCallStates.RECONNECT
        else
          current_state = RestCallStates.RETRY
        end
      else
        ret = nil
        err = recv_err
        current_state = RestCallStates.COMPLETE
      end
    elseif current_state == RestCallStates.RECONNECT then

      reconnect(client)
      current_state = RestCallStates.RETRY
    elseif current_state == RestCallStates.RETRY then
      bytes_sent, send_err, _idx = nil, nil, 0
      response, recv_err, partial = nil, nil, nil
      current_state = RestCallStates.SEND
      socket.sleep(backoff())
    end
  until current_state == RestCallStates.COMPLETE

  return ret, err
end

local function make_socket(host, port, wrap_ssl)
  local sock, err = socket.tcp()

  if err ~= nil or (not sock) then
    return nil, (err or "unknown error creating TCP socket")
  end

  -- sock:setoption("keepalive", true)
  _, err = sock:connect(host, port)

  if err then return nil, err end

  if wrap_ssl then
    sock, err =
    ssl.wrap(sock, { mode = "client", protocol = "any", verify = "none", options = "all" })
    if sock ~= nil then
      _, err = sock:dohandshake()
    elseif err ~= nil then
      log.error("Error setting up TLS: " .. err)
    end
  end

  if err ~= nil then sock = nil end

  return sock, err
end

---@class RestClient
---
---@field base_url table `net.url` URL table
---@field socket table `cosock` TCP socket
local RestClient = {}
RestClient.__index = RestClient

function RestClient.one_shot_get(full_url, additional_headers, socket_builder)
  local url_table = utils.force_url_table(full_url)

  return RestClient.new(url_table.scheme .. "://" .. url_table.host .. ":" .. url_table.port, socket_builder):get(
    url_table.path, additional_headers
  )
end

function RestClient.one_shot_post(full_url, body, additional_headers, socket_builder)
  local url_table = utils.force_url_table(full_url)

  return RestClient.new(url_table.scheme .. "://" .. url_table.host, socket_builder):post(
    url_table.path, body, additional_headers
  )
end

function RestClient:update_base_url(new_url)
  if self.socket ~= nil then
    self.socket:close()
    self.socket = nil
  end

  self.base_url = utils.force_url_table(new_url)
end

local function _build_request(method, path, host, additional_headers)
  local request = Request.new(method, path, nil):add_header("user-agent", "smartthings-lua-edge-driver")
                                                :add_header("host", string.format("%s", host))

  if additional_headers ~= nil and type(additional_headers) == "table" then
    for k, v in pairs(additional_headers) do request = request:add_header(k, v) end
  end

  return request
end

local function _build_request_with_body(method, path, host, additional_headers, body_string)
  local request = _build_request(method, path, host, additional_headers)
  request:append_body(body_string)
  return request
end

function RestClient:get(path, additional_headers, retry_fn)
  local request = _build_request("GET", path, self.base_url.host, additional_headers)
  return execute_request(self, request, retry_fn)
end

function RestClient:post(path, body_string, additional_headers, retry_fn)
  local request =
    _build_request_with_body("POST", path, self.base_url.host, additional_headers, body_string)

  return execute_request(self, request, retry_fn)
end

function RestClient:put(path, body_string, additional_headers, retry_fn)
  local request =
    _build_request_with_body("PUT", path, self.base_url.host, additional_headers, body_string)

  return execute_request(self, request, retry_fn)
end

function RestClient.new(base_url, sock_builder)
  base_url = utils.force_url_table(base_url)

  if type(sock_builder) ~= "function" then sock_builder = make_socket end

  return setmetatable({ base_url = base_url, socket_builder = sock_builder, socket = nil }, RestClient)
end

return RestClient
