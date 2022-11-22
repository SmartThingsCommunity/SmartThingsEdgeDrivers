-- Copyright 2022 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local cosock = require "cosock"
local socket = require "cosock.socket"
local http = cosock.asyncify "socket.http" -- TODO use luncheon instead
--- local ltn12 = require "ltn12"
local log = require "log"
local xml2lua = require "xml2lua"
local xml_handler = require "xmlhandler.tree"
local utils = require "st.utils"
local command = require "command"

local ltn12 = require "socket.ltn12"

--- @module samsung-audio.Disco
local Disco = {}


local function tablefind(t, path)
  local pathelements = string.gmatch(path, "([^.]+)%.?")
  local item = t

  for element in pathelements do
    if type(item) ~= "table" then item = nil; break end

    item = item[element]
  end

  return item
end


local function fetch_device_metadata(url)
  -- to respond with chunked encoding, must use ltn12 sink
  local responsechunks = {}
  local body,status,headers = http.request{
    url = url,
    sink = ltn12.sink.table(responsechunks),
  }

  local response = table.concat(responsechunks)
  log.trace("metadata response status", body, status, headers)
  if status ~= 200 then
    log.error("metadata request failed ("..tostring(status)..")\n"..response)
    return nil, "request failed: "..tostring(status)
  end

  local handler = xml_handler:new()
  local xml_parser = xml2lua.parser(handler)
  xml_parser:parse(response)

  if not handler.root then
    log.error("unable to parse device metadata as xml")
    return nil, "xml parse error"
  end

  local parsed_xml = handler.root

  -- check if we parsed a <root> element
  if not parsed_xml.root then
    return nil
  end

  return {
    name = tablefind(parsed_xml, "root.device.friendlyName"),
    model = tablefind(parsed_xml, "root.device.modelName")
  }
end


local function process_response(val)
  local info = {}
  val = string.gsub(val, "HTTP/1.1 200 OK\r\n", "", 1)
  for k, v in string.gmatch(val, "([%g]+): ([%g ]*)\r\n") do info[string.lower(k)] = v end
  return info
end

function Disco.find(deviceid, callback)
  log.info("handling discovery find...")

  local s = assert(socket.udp(), "create discovery socket")
  local listen_ip = "0.0.0.0"
  local listen_port = 0

  local multicast_ip = "239.255.255.250"
  local multicast_port = 1900
  local multicast_msg = table.concat({
    "M-SEARCH * HTTP/1.1", "HOST: 239.255.255.250:1900",
    "MAN: \"ssdp:discover\"",
    "MX: 2", "ST: urn:samsung.com:device:RemoteControlReceiver:1", "\r\n",
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
      local ip, port = headers["location"]:match(
                             "http://([^,/]+):([^/]+)") -- TODO : We need to check the xml filename for samsung audio device for ex: http://192.168.0.1:59666/rootDesc.xml
      local id = headers["usn"]

      -- TODO how do I know the device that responded is actually a samsung-audio device
      -- potentially will need to make a request to the endpoint
      local meta = fetch_device_metadata(headers["location"])
      local speaker_name = "samsung-audio speaker"
      local speaker_model = "unknown samsung-audio"
      if not meta then
          meta = {}
          log.trace("fetch_device_metadata INFO is NULL")
      else
          speaker_name = meta.name
          speaker_model = meta.model
      end

      if rip ~= ip then
        log.warn(string.format(
                   "recieved discovery response with reported (%s) & source IP (%s) mismatch, ignoring",
                   rip, ip))
        log.debug(rip, "!=", ip)
      elseif ip and id then
        callback({id = id, ip = ip, raw = val, name = speaker_name, model = speaker_model})

        if id == deviceid then
          -- check if the speaker we just found was the one we were looking for
          break
        end
      end
    elseif rip == "timeout" then
      break
    else
      error(string.format("error receiving discovery replies: %s", rip))
    end
  end
  s:close()
end

return Disco
