---@module 'utils'
local utils = {}
-- build a exponential backoff time value generator
--
-- max: the maximum wait interval (not including `rand factor`)
-- inc: the rate at which to exponentially back off
-- rand: a randomization range of (-rand, rand) to be added to each interval
function utils.backoff_builder(max, inc, rand)
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

function utils.labeled_socket_builder(label)
  local log = require "log"
  local socket = require "cosock.socket"
  local ssl = require "cosock.ssl"

  label = (label or "")
  if #label > 0 then
    label = label .. " "
  end

  local function make_socket(host, port, wrap_ssl)
    log.info(
      string.format(
        "%sCreating TCP socket for REST Connection", label
      )
    )
    local _ = nil
    local sock, err = socket.tcp()
    if err ~= nil or (not sock) then
      return nil, (err or "unknown error creating TCP socket")
    end

    log.info(
      string.format(
        "%sSetting TCP socket timeout for REST Connection", label
      )
    )
    _, err = sock:settimeout(60)
    if err ~= nil then
      return nil, "settimeout error: " .. err
    end

    log.info(
      string.format(
        "%sConnecting TCP socket for REST Connection", label
      )
    )
    _, err = sock:connect(host, port)

    if err then return nil, err end

    if wrap_ssl then
      log.info(
        string.format(
          "%sCreating SSL wrapper for for REST Connection", label
        )
      )
      sock, err =
        ssl.wrap(sock, {mode = "client", protocol = "any", verify = "none", options = "all"})
      if err ~= nil then
         return nil, "SSL wrap error: " .. err
      end
      log.info(
        string.format(
          "%sPerforming SSL handshake for for REST Connection", label
        )
      )
        _, err = sock:dohandshake()
      if err ~= nil then
        return nil, "Error with SSL handshake: " .. err
      end
    end

    return sock, err
  end
  return make_socket
end

return utils
