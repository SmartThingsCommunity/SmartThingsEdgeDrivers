--  Copyright 2021 SmartThings
--
--  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except
--  in compliance with the License. You may obtain a copy of the License at:
--
--      http://www.apache.org/licenses/LICENSE-2.0
--
--  Unless required by applicable law or agreed to in writing, software distributed under the License is distributed
--  on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License
--  for the specific language governing permissions and limitations under the License.

local socket = require("socket")
local log = require("log")

--------------------------------------------------------------------------------------------
-- ThingSim device discovery
--------------------------------------------------------------------------------------------

local looking_for_all = setmetatable({}, {__index = function() return true end})

local function process_response(val)
  local info = {}
  val = string.gsub(val, "HTTP/1.1 200 OK\r\n", "", 1)
  for k, v in string.gmatch(val, "([%g]+): ([%g ]*)\r\n") do
    info[string.lower(k)] = v
  end
  return info
end

local function device_discovery_metadata_generator(thing_ids, callback)
  local looking_for = {}
  local number_looking_for
  local number_found = 0
  if thing_ids ~= nil then
    number_looking_for = #thing_ids
    for _, id in ipairs(thing_ids) do looking_for[id] = true end
  else
    looking_for = looking_for_all
    number_looking_for = math.maxinteger
  end

  local s = socket.udp()
  assert(s)
  local listen_ip = interface or "0.0.0.0"
  local listen_port = 0

  local multicast_ip = "239.255.255.250"
  local multicast_port = 1900
  local multicast_msg =
  'M-SEARCH * HTTP/1.1\r\n' ..
  'HOST: 239.255.255.250:1982\r\n' ..
  'MAN: "ssdp:discover"\r\n' ..
  'MX: 1\r\n' ..
  'ST: urn:smartthings-com:device:thingsim:1\r\n'

  -- Create bind local ip and port
  -- simulator will unicast back to this ip and port
  assert(s:setsockname(listen_ip, listen_port))
  local timeouttime = socket.gettime() + 8
  s:settimeout(8)

  local ids_found = {} -- used to filter duplicates
  assert(s:sendto(multicast_msg, multicast_ip, multicast_port))
  while number_found < number_looking_for do
    local time_remaining = math.max(0, timeouttime-socket.gettime())
    s:settimeout(time_remaining)
    local val, rip, rport = s:receivefrom()
    if val then
      log.trace(val)
      local headers = process_response(val)
      local ip, port = headers["location"]:match("http://([^,]+):([^/]+)")
      local rpcip, rpcport = (headers["rpc.smartthings.com"] or ""):match("rpc://([^,]+):([^/]+)")
      local httpip, httpport = (headers["http.smartthings.com"] or ""):match("http://([^,]+):([^/]+)")
      local id = headers["usn"]:match("uuid:([^:]+)")
      local name = headers["name.smartthings.com"]

      if rip ~= ip then
        log.warn("recieved discovery response with reported & source IP mismatch, ignoring")
      elseif ip and port and id and looking_for[id] and not ids_found[id] then
        ids_found[id] = true
	      number_found = number_found + 1
        -- TODO: figure out if it's possible to make recursive coroutines work inside cosock
        --coroutine.yield({ip = ip, port = port, info = info})
        callback({id = id, ip = ip, port = port, rpcport = rpcport, httpport = httpport, name = name})
      else
        log.debug("found device not looking for:", id)
      end
    elseif rip == "timeout" then
      return nil
    else
      error(string.format("error receving discovery replies: %s", rip))
    end
  end
end

local function find_cb(thing_ids, cb)
  device_discovery_metadata_generator(thing_ids, cb)
end

local function find(thing_ids)
  local thingsmeta = {}
  local function cb(metadata) table.insert(thingsmeta, metadata) end
  find_cb(thing_ids, cb)
  return thingsmeta
end


return {
  find = find,
  find_cb = find_cb,
}
