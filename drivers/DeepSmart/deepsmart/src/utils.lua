local log=require('log')

local utils = {}
utils.base = {0, 0x40, 0x7A, 0x10, 0xF3, 0x5A, 0, 0}

function utils.tonumber(str)
  local len = #str
  local bytes = {}
  for i=1,8 do
    bytes[i] = 0
  end
  local lowstr = str
  local highstr = nil
  if (len > 14) then
    lowstr = string.sub(str,len-13)
    highstr = string.sub(str, 1, len-14)
  end
  local low = tonumber(lowstr)
  local pos = 1
  while(low > 0) do
    bytes[pos] = (low%256)
    low = ((low-bytes[pos])>>8)
    pos = pos+1
  end
  -- high
  local high = 0
  if (highstr ~= nil) then
    high = tonumber(highstr)
  end
  local sec = 0
  for i=1,8 do
    local fir = high * utils.base[i] + bytes[i] + sec
    sec = ((fir-(fir%256))>>8)
    bytes[i] = (fir%256)
  end
  return bytes
end

function utils.tobytes(num)
  local bytes = {}
  local pos = 1
  local tmp = num
  while(tmp > 0) do
    bytes[pos] = (tmp%256)
    tmp = ((tmp-bytes[pos])>>8)
    pos = pos+1
  end
  return bytes
end

function utils.loadfile(file)
  local fp = io.open(file, 'r')
  if (fp) then
    local content = fp:read('*a')
    fp:close()
    return content
  else
    return ''
  end
end


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
  return tostring(number) == tostring(0 / 0)
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

function utils.labeled_socket_builder(label, ssl_config)
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
    if err ~= nil then
      return nil, "Connect error: " .. err
    end

    log.info(
      string.format(
        "%sSet Keepalive for TCP socket for REST Connection", label
      )
    )
    _, err = sock:setoption("keepalive", true)
    if err ~= nil then
      return nil, "Setoption error: " .. err
    end

    if wrap_ssl then
      log.info(
        string.format(
          "%sCreating SSL wrapper for for REST Connection", label
        )
      )
      sock, err =
          ssl.wrap(sock, ssl_config)
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

    log.info(
      string.format(
        "%sSuccessfully created TCP connection", label
      )
    )
    return sock, err
  end
  return make_socket
end

--- From https://gist.github.com/sapphyrus/fd9aeb871e3ce966cc4b0b969f62f539
--- MIT licensed
function utils.deep_table_eq(tbl1, tbl2)
  if tbl1 == tbl2 then
    return true
  elseif type(tbl1) == "table" and type(tbl2) == "table" then
    for key1, value1 in pairs(tbl1) do
      local value2 = tbl2[key1]

      if value2 == nil then
        -- avoid the type call for missing keys in tbl2 by directly comparing with nil
        return false
      elseif value1 ~= value2 then
        if type(value1) == "table" and type(value2) == "table" then
          if not utils.deep_table_eq(value1, value2) then
            return false
          end
        else
          return false
        end
      end
    end

    -- check for missing keys in tbl1
    for key2, _ in pairs(tbl2) do
      if tbl1[key2] == nil then
        return false
      end
    end

    return true
  end

  return false
end



return utils

