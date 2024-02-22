local socket = require "cosock.socket"
local st_utils = require "st.utils"

local lb_utils = require "lunchbox.util"
local utils = require "utils"
local Request = require "luncheon.request"
local Response = require "luncheon.response"

local api_version = require("version").api

local RestCallStates = {
  SEND = "Send",
  RECEIVE = "Receive",
  RETRY = "Retry",
  RECONNECT = "Reconnect",
  COMPLETE = "Complete",
}

local function connect(client)
  local port = 80
  local use_ssl = false

  if client.base_url.scheme == "https" then
    port = 443
    use_ssl = true
  end

  if client.base_url.port ~= port then port = client.base_url.port end
  local sock, err = client.socket_builder(client.base_url.host, port, use_ssl)

  if sock == nil then
    client.socket = nil
    return false, err
  end

  client.socket = sock
  return true
end

local function reconnect(client)
  if client.socket ~= nil then
    client.socket:close()
    client.socket = nil
  end
  return connect(client)
end

local function send_request(client, request)
  if client.socket == nil then
    return nil, "no socket available"
  end
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

  local original_body, err = original_response:get_body()
  if type(original_body) ~= "string" or err ~= nil then
    return original_body, (err or "unexpected nil in error position")
  end
  local next_chunk_bytes = tonumber(original_body, 16)
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
        else
          return nil, next_err
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
  if api_version >= 9 then
    local response, err = Response.tcp_source(sock)
    if err or (not response) then return response, (err or "unknown error") end
    return response, response:fill_body()
  end
  -- called select right before passing in so we receive immediately
  local initial_recv, initial_err, partial = Response.source(function() return sock:receive('*l') end)

  local full_response = nil

  if initial_recv ~= nil then
    local headers = initial_recv:get_headers()

    if headers and headers:get_one("Transfer-Encoding") == "chunked" then
      local response, err = parse_chunked_response(initial_recv, sock)
      if err ~= nil then
        return nil, err
      end
      full_response = response
    else
      local content_length_header = (headers and headers:get_one("Content-length")) or nil
      if content_length_header then
        local content_length = tonumber(content_length_header)
        if type(content_length) ~= "number" then
          return nil, string.format("content_length is not a number: %s", st_utils.stringify_table(content_length_header))
        end

        body, err, partial = sock:receive(content_length)
        if err ~= nil then
          return nil, err, partial
        end

        if body == nil then
          return nil, string.format("Unexpected nil body response, partial response receive: %s", partial)
        end

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
  if not client._active then
    return nil, "Called `execute request` on a terminated REST Client"
  end

  if client.socket == nil then
    local success, err = connect(client)
    if not success then return nil, err end
  end

  local should_retry = retry_fn
  if type(should_retry) ~= "function" then
    should_retry = function() return false end
  end

  -- send output
  local _bytes_sent, send_err, _idx = nil, nil, 0
  -- recv output
  local response, recv_err, _partial = nil, nil, nil
  -- return values
  local ret, err = nil, nil

  local backoff = utils.backoff_builder(60, 1, 0.1)
  local current_state = RestCallStates.SEND

  repeat
    local retry = should_retry()
    if current_state == RestCallStates.SEND then
      backoff = utils.backoff_builder(60, 1, 0.1)
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
      local success, reconn_err = reconnect(client)
      if success then
        current_state = RestCallStates.RETRY
      elseif not retry then
        ret = nil
        err = reconn_err
        current_state = RestCallStates.COMPLETE
      else
        socket.sleep(backoff())
      end
    elseif current_state == RestCallStates.RETRY then
      bytes_sent, send_err, _idx = nil, nil, 0
      response, recv_err, partial = nil, nil, nil
      current_state = RestCallStates.SEND
      socket.sleep(backoff())
    end
  until current_state == RestCallStates.COMPLETE

  return ret, err
end

---@class RestClient
---
---@field base_url table `net.url` URL table
---@field socket table `cosock` TCP socket
local RestClient = {}
RestClient.__index = RestClient

function RestClient.one_shot_get(full_url, additional_headers, socket_builder)
  local url_table = lb_utils.force_url_table(full_url)
  local client = RestClient.new(url_table.scheme .. "://" .. url_table.host .. ":" .. url_table.port, socket_builder)
  local ret, err = client:get(url_table.path, additional_headers)
  client:shutdown()
  client = nil
  return ret, err
end

function RestClient.one_shot_post(full_url, body, additional_headers, socket_builder)
  local url_table = lb_utils.force_url_table(full_url)
  local client = RestClient.new(url_table.scheme .. "://" .. url_table.host .. ":" .. url_table.port, socket_builder)
  local ret, err = client:post(url_table.path, body, additional_headers)
  client:shutdown()
  client = nil
  return ret, err
end

function RestClient:close_socket()
  if self.socket ~= nil and self._active then
    self.socket:close()
    self.socket = nil
  end
end

function RestClient:shutdown()
  self:close_socket()
  self._active = false
end

function RestClient:update_base_url(new_url)
  if self.socket ~= nil then
    self.socket:close()
    self.socket = nil
  end

  self.base_url = lb_utils.force_url_table(new_url)
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
  base_url = lb_utils.force_url_table(base_url)

  if type(sock_builder) ~= "function" then sock_builder = utils.labeled_socket_builder("Sonos REST API") end

  return setmetatable({ base_url = base_url, socket_builder = sock_builder, socket = nil, _active = true }, RestClient)
end

return RestClient
