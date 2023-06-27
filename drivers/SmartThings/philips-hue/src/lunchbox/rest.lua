local socket = require "cosock.socket"
local ssl = require "cosock.ssl"
local log = require "log"

local utils = require "utils"
local lb_utils = require "lunchbox.util"
local Request = require "luncheon.request"
local Response = require "luncheon.response"

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
  if not original_body or err ~= nil then
    return nil, err
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
      elseif retry then
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
      elseif retry then
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

local function make_socket(host, port, wrap_ssl)
  log.info_with({hub_logs = true}, "Creating TCP socket for Hue REST Connection")
  local sock, err = socket.tcp()

  if err ~= nil or (not sock) then
    return nil, (err or "unknown error creating TCP socket")
  end

  log.info_with({hub_logs = true}, "Setting TCP socket timeout for Hue REST Connection")
  _, err = sock:settimeout(60)
  if err ~= nil then
    return nil, "settimeout error: " .. err
  end

  log.info_with({hub_logs = true}, "Connecting TCP socket for Hue REST Connection")
  _, err = sock:connect(host, port)
  if err ~= nil then
    return nil, "Connect error: " .. err
  end

  log.info_with({hub_logs = true}, "Set Keepalive for TCP socket for Hue REST Connection")
  _, err = sock:setoption("keepalive", true)
  if err ~= nil then
    return nil, "Setoption error: " .. err
  end

  if wrap_ssl then
    log.info_with({hub_logs = true}, "Creating SSL wrapper for for Hue REST Connection")
    sock, err =
      ssl.wrap(sock, {mode = "client", protocol = "any", verify = "none", options = "all"})
    if err ~= nil then
       return nil, "SSL wrap error: " .. err
    end
    log.info_with({hub_logs = true}, "Performing SSL handshake for for Hue REST Connection")
      _, err = sock:dohandshake()
    if err ~= nil then
      return nil, "Error with SSL handshake: " .. err
    end
  end

  log.info_with({hub_logs = true}, "Successfully created TCP connection for Hue")
  return sock, err
end

---@class RestClient
---
---@field base_url table `net.url` URL table
---@field socket table `cosock` TCP socket
local RestClient = {}
RestClient.__index = RestClient

function RestClient.one_shot_get(full_url, additional_headers, socket_builder)
  local url_table = lb_utils.force_url_table(full_url)
  local client = RestClient.new(url_table.scheme .. "://" .. url_table.host, socket_builder)
  local ret, err = client:get(url_table.path, additional_headers)
  client:shutdown()
  client = nil
  return ret, err
end

function RestClient.one_shot_post(full_url, body, additional_headers, socket_builder)
  local url_table = lb_utils.force_url_table(full_url)
  local client = RestClient.new(url_table.scheme .. "://" .. url_table.host, socket_builder)
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

function RestClient:get(path, additional_headers, retry_fn)
  local request = Request.new("GET", path, nil):add_header(
                    "user-agent", "smartthings-lua-edge-driver"
                  ):add_header("host", string.format("%s", self.base_url.host)):add_header(
                    "connection", "keep-alive"
                  )

  if additional_headers ~= nil and type(additional_headers) == "table" then
    for k, v in pairs(additional_headers) do request = request:add_header(k, v) end
  end

  return execute_request(self, request, retry_fn)
end

function RestClient:post(path, body_string, additional_headers, retry_fn)
  local request = Request.new("POST", path, nil):add_header(
                    "user-agent", "smartthings-lua-edge-driver"
                  ):add_header("host", string.format("%s", self.base_url.host)):add_header(
                    "connection", "keep-alive"
                  )

  if additional_headers ~= nil and type(additional_headers) == "table" then
    for k, v in pairs(additional_headers) do request = request:add_header(k, v) end
  end

  request = request:append_body(body_string)

  return execute_request(self, request, retry_fn)
end

function RestClient:put(path, body_string, additional_headers, retry_fn)
  local request = Request.new("PUT", path, nil):add_header(
                    "user-agent", "smartthings-lua-edge-driver"
                  ):add_header("host", string.format("%s", self.base_url.host)):add_header(
                    "connection", "keep-alive"
                  )

  if additional_headers ~= nil and type(additional_headers) == "table" then
    for k, v in pairs(additional_headers) do request = request:add_header(k, v) end
  end

  request = request:append_body(body_string)

  return execute_request(self, request, retry_fn)
end

function RestClient.new(base_url, sock_builder)
  base_url = lb_utils.force_url_table(base_url)

  if type(sock_builder) ~= "function" then sock_builder = make_socket end

  return
    setmetatable({base_url = base_url, socket_builder = sock_builder, socket = nil, _active = true}, RestClient)
end

local utils = require "utils"
local logged_funcs = {}
for key, val in pairs(RestClient) do
  if type(val) == "function" then
    logged_funcs[key] = utils.log_func_wrapper(val, key)
  end
end

for key, val in pairs(logged_funcs) do
  RestClient[key] = val
end

return RestClient
