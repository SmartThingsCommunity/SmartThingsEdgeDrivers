local socket = require('socket')
local cosock = require "cosock"
local log = require('log')
local config = require('config')
local utils = require('utils.utils')


DEEPSMART_SSDP_SEARCH_TERM = "DEEPSMART-ARM"


local SSDP = {}
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
function SSDP.search(search_term, callback, is_add)
  -- UDP socket initialization
  local upnp = socket.udp()
  local _,err = upnp:setsockname('0.0.0.0', 0)
  if err then
    log.error(string.format("udp socket failure setsockname: %s", err))
    return false,err
  end
  local timeout = socket.gettime() + config.MC_TIMEOUT + 1
  local mx = 2
  -- broadcasting request
  log.info('===== SCANNING NETWORK...')
   local multicast_msg = table.concat({
     "M-SEARCH * HTTP/1.1",
     "HOST: 239.255.255.250:1900",
     'MAN: "ssdp:discover"', -- yes, there are really supposed to be quotes in this one
     string.format("MX: %s", mx),
     string.format("ST: %s", search_term),
     "\r\n"
   }, "\r\n")
  local _, err = upnp:sendto(multicast_msg, config.MC_ADDRESS, config.MC_PORT)
  if err then
    log.error(string.format("udp socket failure sendto: %s", err))
    return false,err
  end
  local idx = 1
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
      local beginpos,endpos = string.find(usn, 'uuid:')
      local uuid = string.sub(usn, endpos+1)
      beginpos,endpos = string.find(uuid, '::')
      uuid = string.sub(uuid, 1,beginpos-1)
      log.info('usn '..usn..' uuid '..uuid..' ip '..ip)
      if callback ~= nil and type(callback) == "function" then
        callback(uuid, ip, 8000, is_add)
      end
    else
      break
    end
  end
  log.info('===== SCANNING NETWORK OVER')
  -- close udp socket
  upnp:close()

  return true,nil
end


return SSDP
