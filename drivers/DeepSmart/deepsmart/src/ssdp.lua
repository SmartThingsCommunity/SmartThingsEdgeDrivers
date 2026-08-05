local socket = require('socket')
local log = require('log')
local config = require('config')




local SSDP = {}

local DEEPSMART_SSDP_SEARCH_TERM = "DEEPSMART-ARM"
-----------------------
-- SSDP Response parser
local function parse_ssdp(data)
  local res = {}
  res.status = data:sub(0, data:find('\r\n'))
  for k, v in data:gmatch('([%w-]+): ([%a+-: /=]+)') do
    local key = k:lower()
    log.info('parse key '..key..' val '..v)
    res[key] = v
  end
  return res
end


-- This function enables a UDP
-- Socket and broadcast a single
-- M-SEARCH request, i.e., it
-- must be looped appart.
function SSDP.search(callback)
  local bridges = {}
  -- UDP socket initialization
  local upnp = socket.udp()
  local _,err = upnp:setsockname('0.0.0.0', 0)
  if err then
    log.error(string.format("udp socket failure setsockname: %s", err))
    return false,bridges,err
  end
  -- use broadcast to find wisers as wifi router's group cast is forbidden by default(need login to router to start group cast)
  upnp:setoption('broadcast', true)
  local timeout = socket.gettime() + config.MC_TIMEOUT + 1
  local mx = 2
  -- broadcasting request
  log.info('===== SCANNING NETWORK...')
  local multicast_msg = table.concat({
    "M-SEARCH * HTTP/1.1",
    "HOST: 255.255.255.255:1900",
    'MAN: "ssdp:discover"', -- yes, there are really supposed to be quotes in this one
    string.format("MX: %s", mx),
    string.format("ST: %s", DEEPSMART_SSDP_SEARCH_TERM),
    "\r\n"
  }, "\r\n")
  local _, err = upnp:sendto(multicast_msg, config.MC_ADDRESS, config.MC_PORT)
  if err then
    log.error(string.format("udp socket failure sendto: %s", err))
    return false,bridges,err
  end
  while true do
    -- Socket will wait n seconds
    -- based on the s:setoption(n)
    -- to receive a response back.
    local time_remaining = math.max(0, timeout - socket.gettime())
    upnp:settimeout(time_remaining)
    local res,ip = upnp:receivefrom()
    if (res ~= nil) then
      log.info('recv wiser '..res..' from '..ip)
      local headers = parse_ssdp(res)
      -- Device metadata
      local usn = headers.usn
      local uuid = usn:match("uuid:(%d+)::")
      if (uuid ~= nil) then
        log.info('usn '..usn..' uuid '..uuid..' ip '..ip)
        if callback ~= nil and type(callback) == "function" then
          callback(uuid, ip)
        end
        bridges[uuid] = ip
      end
    else
      break
    end
  end
  log.info('===== SCANNING NETWORK OVER')
  -- close udp socket
  upnp:close()

  return true,bridges,nil
end


return SSDP
