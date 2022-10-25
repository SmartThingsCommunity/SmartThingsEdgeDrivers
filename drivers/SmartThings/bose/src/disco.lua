--  Copyright 2021 SmartThings
--
--  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
--  except in compliance with the License. You may obtain a copy of the License at:
--
--      http://www.apache.org/licenses/LICENSE-2.0
--
--  Unless required by applicable law or agreed to in writing, software distributed under the
--  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
--  either express or implied. See the License for the specific language governing permissions
--  and limitations under the License.
--

local cosock = require "cosock"
local socket = require "cosock.socket"
local http = cosock.asyncify "socket.http" -- TODO use luncheon instead
local ltn12 = require "ltn12"
local log = require "log"
local xml2lua = require "xml2lua"
local xml_handler = require "xmlhandler.tree"
local utils = require "st.utils"
local command = require "command"

--- @module bose.Disco
local Disco = {}

local function process_response(val)
  local info = {}
  val = string.gsub(val, "HTTP/1.1 200 OK\r\n", "", 1)
  for k, v in string.gmatch(val, "([%g]+): ([%g ]*)\r\n") do info[string.lower(k)] = v end
  return info
end

function Disco.find(deviceid, callback)
  local s = assert(socket.udp(), "create discovery socket")

  local listen_ip = "0.0.0.0"
  local listen_port = 0

  local multicast_ip = "239.255.255.250"
  local multicast_port = 1900
  local multicast_msg = table.concat({
    "M-SEARCH * HTTP/1.1", "HOST: 239.255.255.250:1900",
    "MAN: \"ssdp:discover\"", -- yes, there are really supposed to be quotes in this one
    "MX: 2", "ST: urn:schemas-upnp-org:device:MediaRenderer:1", "\r\n",
  }, "\r\n")

  -- bind local ip and port
  -- device will unicast back to this ip and port
  assert(s:setsockname(listen_ip, listen_port), "discovery socket setsockname")
  local timeouttime = socket.gettime() + 3 -- 3 second timeout, `MX` + 1 for network delay

  local ids_found = {} -- used to filter duplicates
  local number_found = 0

  log.debug("sending discovery multicast request")
  assert(s:sendto(multicast_msg, multicast_ip, multicast_port))
  while true do
    local time_remaining = math.max(0, timeouttime - socket.gettime())
    s:settimeout(time_remaining)
    local val, rip, _ = s:receivefrom()
    if val then
      local headers = process_response(val)
      local ip, port, id = headers["location"]:match(
                             "http://([^,/]+):([^/]+)/%a+/BO5EBO5E%-F00D%-F00D%-FEED%-([%g-]+).xml")

      -- TODO how do I know the device that responded is actually a bose device
      -- potentially will need to make a request to the endpoint
      -- fetch_device_metadata()
      if rip ~= ip then
        log.warn(string.format(
                   "[%s]recieved discovery response with reported (%s) & source IP (%s) mismatch, ignoring",
                   deviceid, rip, ip))
        log.debug(rip, "!=", ip)
      elseif ip and id then
        callback({id = id, ip = ip, raw = val})

        if deviceid then
          -- check if the speaker we just found was the one we were looking for
          if deviceid == id then break end
        end
      end
    elseif rip == "timeout" then
      break
    else
      error(string.format("[%s]error receving discovery replies: %s", deviceid, rip))
    end
  end
  s:close()
end

return Disco
