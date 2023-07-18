local log = require "log"
---@module 'utils'
local utils = {}

local MAC_ADDRESS_STR_LEN = 12

function utils.str_starts_with(str, start)
  return str:sub(1, #start) == start
end
function utils.is_nan(number)
  -- IEEE 754 dictates that NaN compares falsey to everything, including itself.
  if number ~= number then
    return true
  end

  -- If someone passes in something that isn't a Number type, it'll pass the above check.
  -- Philosophical question: Something that isn't a number can't technicaly have the value
  -- of "nan" but "nan" stands for "not a number", so what do we do here?
  if type(number) ~= "number" then
    log.warn(string.format("utils.is_nan received value of type %s as argument, returning true", type(number)))
    return true
  end

  -- In the event that something goes wrong with the above two things,
  -- we simply compare the tostring against a known NaN value.
  return tostring(number) == tostring(0/0)
end

--- Only checked during `added` callback
---@param device HueDevice
---@return boolean
function utils.is_edge_bridge(device)
  return device.device_network_id and #device.device_network_id == MAC_ADDRESS_STR_LEN and
  not (device.data and device.data.username)
end

--- Only checked during `added` callback
---@param device HueDevice
---@return boolean
function utils.is_edge_light(device)
  return device.parent_assigned_child_key and #device.parent_assigned_child_key > MAC_ADDRESS_STR_LEN and
  not (device.data and device.data.username and device.data.bulbId)
end

--- Only checked during `added` callback
---@param device HueDevice
---@return boolean
function utils.is_dth_bridge(device)
  return device.data ~= nil
      and not device.data.bulbId
      and device.data.username ~= nil
end

--- Only checked during `added` callback
---@param device HueDevice
---@return boolean
function utils.is_dth_light(device)
  return device.data ~= nil
      and device.data.bulbId ~= nil
      and device.data.username ~= nil
end

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
        "%sCreating TCP socket for Hue REST Connection", label
      )
    )
    local _ = nil
    local sock, err = socket.tcp()

    if err ~= nil or (not sock) then
      return nil, (err or "unknown error creating TCP socket")
    end

    log.info(
      string.format(
        "%sSetting TCP socket timeout for Hue REST Connection", label
      )
    )
    _, err = sock:settimeout(60)
    if err ~= nil then
      return nil, "settimeout error: " .. err
    end

    log.info(
      string.format(
        "%sConnecting TCP socket for Hue REST Connection", label
      )
    )
    _, err = sock:connect(host, port)
    if err ~= nil then
      return nil, "Connect error: " .. err
    end

    log.info(
      string.format(
        "%sSet Keepalive for TCP socket for Hue REST Connection", label
      )
    )
    _, err = sock:setoption("keepalive", true)
    if err ~= nil then
      return nil, "Setoption error: " .. err
    end

    if wrap_ssl then
      log.info(
        string.format(
          "%sCreating SSL wrapper for for Hue REST Connection", label
        )
      )
      sock, err =
          ssl.wrap(sock, { mode = "client", protocol = "any", verify = "none", options = "all" })
      if err ~= nil then
        return nil, "SSL wrap error: " .. err
      end
      log.info(
        string.format(
          "%sPerforming SSL handshake for for Hue REST Connection", label
        )
      )
      _, err = sock:dohandshake()
      if err ~= nil then
        return nil, "Error with SSL handshake: " .. err
      end
    end

    log.info(
      string.format(
        "%sSuccessfully created TCP connection for Hue", label
      )
    )
    return sock, err
  end
  return make_socket
end

return utils
