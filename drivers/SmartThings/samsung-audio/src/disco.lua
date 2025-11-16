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
local log = require "log"
local xml2lua = require "xml2lua"
local xml_handler = require "xmlhandler.tree"
local ltn12 = require "ltn12"

--- @module samsung-audio.Disco
local Disco = {}

local SAMSUNG_AUDIO_MODEL_NAMES = {
  'WAM7500', 'WAM6500', 'WAM5500', 'WAM3500', 'WAM3501', 'WAM1500', 'WAM1501',
  'WAM1400', 'WAM750', 'WAM550', 'WAM350', 'J8500', 'J7500', 'J6500', 'J650',
  'H750', 'K650', 'K850', 'K950', 'J6500R', 'J7500R', 'J8500R'
}

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

  local udn_value = tablefind(parsed_xml, "root.device.UDN")
  local mac_raw = string.sub(udn_value, -12)
  local mac_val = string.upper(mac_raw)
  log.debug(string.format("SPEAKER_MAC_VAL --> %s", mac_val))

  return {
    name = tablefind(parsed_xml, "root.device.friendlyName"),
    model = tablefind(parsed_xml, "root.device.modelName"),
    mac = mac_val
  }
end


local function process_response(val)
  local info = {}
  val = string.gsub(val, "HTTP/1.1 200 OK\r\n", "", 1)
  for k, v in string.gmatch(val, "([%g]+): ([%g ]*)\r\n") do info[string.lower(k)] = v end
  return info
end

local function check_samsung_model(val)
  log.debug(string.format("Doing the Device Model check --> %s", val))
  for _, model in ipairs(SAMSUNG_AUDIO_MODEL_NAMES) do
    if string.find(val, model) then
      log.debug(string.format("Found the Samsung Audio Device Model --> %s", val))
      return true
    end
  end
  return false
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

  log.debug("sending discovery multicast request")
  assert(s:sendto(multicast_msg, multicast_ip, multicast_port))
  while true do
    local time_remaining = math.max(0, timeouttime - socket.gettime())
    s:settimeout(time_remaining)
    local val, rip, _ = s:receivefrom()
    if val then
      local headers = process_response(val)
      local ip, _ = headers["location"]:match(
                             "http://([^,/]+):([^/]+)") -- TODO : We need to check the xml filename for samsung audio device for ex: http://192.168.0.1:59666/rootDesc.xml

      -- TODO how do I know the device that responded is actually a samsung-audio device
      -- potentially will need to make a request to the endpoint
      local meta = fetch_device_metadata(headers["location"])
      local speaker_name = "samsung-audio speaker"
      local speaker_model = "unknown samsung-audio"
      local id = nil
      if not meta then
          log.trace("fetch_device_metadata INFO is NULL")
      else
          speaker_name = meta.name
          speaker_model = meta.model
          id = meta.mac
      end
      log.debug(string.format("Device Network ID --> %s", id))

      if id == nil then
	log.warn("Device Network ID of discovered device is NIL, ignoring this device")
      elseif rip ~= ip then
        log.warn(string.format(
                   "recieved discovery response with reported (%s) & source IP (%s) mismatch, ignoring",
                   rip, ip))
        log.debug(rip, "!=", ip)
      elseif not check_samsung_model(speaker_model) then  -- to know the device that responded is actually a samsung-audio device
	log.warn("Found non-samsung speaker device, ignoring this device")
      elseif ip and id then
	if deviceid then  -- this is device init flow
	  if id == deviceid then -- check if the speaker we just found was the one we were looking for
            callback({id = id, ip = ip, raw = val, name = speaker_name, model = speaker_model})
            log.debug(string.format("Found the Target Device in Device Init Discovery --> %s", id))
            break
	  else
	    log.debug(string.format("Found the Different Device during Device Init Discovery --> %s", id))
	  end
	else  -- this is device onboarding/search flow
	  callback({id = id, ip = ip, raw = val, name = speaker_name, model = speaker_model})
          log.debug(string.format("Found the Devices during Device Onboarding Discovery --> %s", id))
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
