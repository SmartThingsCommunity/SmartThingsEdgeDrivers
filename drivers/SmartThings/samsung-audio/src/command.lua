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
local http = cosock.asyncify "socket.http"
local ltn12 = require "ltn12"
local xml2lua = require "xml2lua"
local xml_handler = require "xmlhandler.tree"
local utils = require "st.utils"
local log = require "log"


local SAMSUNG_AUDIO_HTTP_PORT = 55001

--- @module samsungaudio.Command
local Command = {}

local function format_url(ip, path)
  return string.format("http://%s:%d%s", ip, SAMSUNG_AUDIO_HTTP_PORT, path)
end

local function is_empty(t)
  return not t or (type(t) == "table" and #t == 0)
end

local function tr(s,mappings)
  return string.gsub(s,
      "(.)",
      function(m)
          if mappings[m] == nil then return m else return mappings[m] end
      end
  )
end

local function handle_http_request(ip, url)
  if not ip then
    log.error("ip value is empty")
    return nil
  end
  if not url then
    log.error("url value is empty")
    return nil
  end

  local resp = {}
  local r, c, h = http.request {
     url = url,
     method = "GET",
     sink = ltn12.sink.table(resp)
   }

  if c ~= 200 then
    log.error(string.format("Error while making http request (%s)", tostring(c)))
    return nil
  end

  handler = xml_handler:new()
  local xml_parser = xml2lua.parser(handler)
  xml_parser:parse(table.concat(resp))
  if is_empty (resp) then
    log.error("UPnP Command Response is Empty")
    return nil
  end

  return {
    handler_res = handler,
  }

end

--  ===============================================================================================
--  SamsungAudio commands to control a speaker or speaker group
--  ===============================================================================================

--- Get devices volume level
---
--- @param ip string
--- @return number between 0 and 100
--- @return err string|nil
function Command.volume(ip)
  log.trace("Triggering UPnP Command Request for [GetVolume]")
  local response_map = nil
  if ip then
   local url = format_url(ip, "/UIC?cmd=<name>GetVolume</name>")
   ret = handle_http_request(ip, url)
   if ret then
     response_map = { volume = ret.handler_res.root.UIC.response.volume, }
   end
  end
  return response_map
end

--- Set the speakers volume level
---
--- @param ip string
--- @return number between 0 and 100
--- @return err string|nil
function Command.set_volume(ip, level)
  log.trace("Triggering UPnP Command Request for [SetVolume]")
  local response_map = nil
  if ip then
   level = math.min(100, math.max(level, 0))
   local encoded_str_vol = "/UIC?cmd=%3Cpwron%3Eon%3C/pwron%3E%3Cname%3ESetVolume%3C/name%3E%3Cp%20type=%22dec%22%20name=%22volume%22%20val=%22" .. level .. "%22%3E%3C/p%3E"
   local url = format_url(ip, encoded_str_vol)
   ret = handle_http_request(ip, url)
   if ret then
     response_map = { volume = ret.handler_res.root.UIC.response.volume, }
   end
  end
  return response_map
end

--- Get speaker name
---
--- @param ip string
--- @return err string|nil
function Command.getSpeakerName(ip)
  log.trace("Triggering UPnP Command Request for [GetSpkName]")
  local response_map = nil
  if ip then
   local url = format_url(ip, "/UIC?cmd=<name>GetSpkName</name>")
   ret = handle_http_request(ip, url)
   if ret then
     response_map = { speakerName = ret.handler_res.root.UIC.response.spkname, }
   end
  end
  return response_map
end

--- Get main info
---
--- @param ip string
--- @return err string|nil
function Command.getMainInfoforGroup(ip)
  log.trace("Triggering UPnP Command Request for [GetMainInfo]")
  local response_map = nil
  if ip then
   local url = format_url(ip, "/UIC?cmd=<name>GetMainInfo</name>")
   ret = handle_http_request(ip, url)
   if ret then
     response_map = { groupmainip = ret.handler_res.root.UIC.response.groupmainip, spkmodelname = ret.handler_res.root.UIC.response.spkmodelname, groupmode = ret.handler_res.root.UIC.response.groupmode,}
   end
  end
  return response_map
end

--- Sends power on command
---
--- @param ip string
--- @return err string|nil
function Command.powerOn(ip)
  log.trace("Triggering UPnP Command Request for [Power On]")
  local response_map = nil
  if ip then
   local press = "/UIC?cmd=%3Cname%3ESetStandbyMode%3C/name%3E%3Cp%20type=%22str%22%20name=%22mode%22%20val=%22on%22/%3E"
   local url = format_url(ip, press)
   ret = handle_http_request(ip, url)
   if ret then
     response_map = { playstatus = ret.handler_res.root.UIC.response.playstatus, }
   end
  end
  return response_map
end

--- Sends power off command
---
--- @param ip string
--- @return err string|nil
function Command.powerOff(ip)
  log.trace("Triggering UPnP Command Request for [Power Off]")
  local response_map = nil
  if ip then
   local press = "/UIC?cmd=%3Cname%3ESetStandbyMode%3C/name%3E%3Cp%20type=%22str%22%20name=%22mode%22%20val=%22off%22/%3E"
   local url = format_url(ip, press)
   ret = handle_http_request(ip, url)
   if ret then
     response_map = { playstatus = ret.handler_res.root.UIC.response.playstatus, }
   end
  end
  return response_map
end

--- Sets Speaker name
---
--- @param ip string
--- @param name string
--- @return err string|nil
function Command.setSpeakerName(ip, name)
  log.trace("Triggering UPnP Command Request for [SetSpkName]")
  local response_map = nil
  if ip then
   local mappings = {["="]="%3D",["\\?"]="%3F", ["&"]="%26"}
   local encodedName = tr(name,mappings)
   local path = string.format("/UIC?cmd=<name>SetSpkName</name><p type=\"cdata\" name=\"spkname\" val=\"empty\"><![CDATA[%s]]></p>", encodedName)
   mappings = {[" "]="%20"}
   path = tr(path, mappings)
   ret = handle_http_request(ip, url)
   if ret then
     response_map = { speakerName = ret.handler_res.root.UIC.response.spkname, }
   end
  end
  return response_map
end

--- Play music on the speaker/speaker group
---
--- @param device table
--- @return err string|nil
function Command.play(ip)
  log.trace("Triggering UPnP Command Request for [Play]")
  local response_map = nil
  if ip then
   local url = format_url(ip, "/UIC?cmd=%3Cpwron%3Eon%3C/pwron%3E%3Cname%3ESetPlaybackControl%3C/name%3E%3Cp%20type=%22str%22%20name=%22playbackcontrol%22%20val=%22resume%22%3E%3C/p%3E")
   ret = handle_http_request(ip, url)
   if ret then
     response_map = { speakerip = ret.handler_res.root.UIC.speakerip, playstatus = ret.handler_res.root.UIC.response.playstatus,}
   end
  end
  return response_map
end

--- Pause music on the speaker/speaker group
---
--- @param device table
--- @return err string|nil
function Command.pause(ip)
  log.trace("Triggering UPnP Command Request for [Pause]")
  local response_map = nil
  if ip then
   local url = format_url(ip, "/UIC?cmd=%3Cpwron%3Eon%3C/pwron%3E%3Cname%3ESetPlaybackControl%3C/name%3E%3Cp%20type=%22str%22%20name=%22playbackcontrol%22%20val=%22pause%22%3E%3C/p%3E")
   ret = handle_http_request(ip, url)
   if ret then
     response_map = { speakerip = ret.handler_res.root.UIC.speakerip, playstatus = ret.handler_res.root.UIC.response.playstatus,}
   end
  end
  return response_map
end

--- Go to previous song for the speaker/speaker group
---
--- @param device table
--- @return err string|nil
function Command.previous(ip)
  log.trace("Triggering UPnP Command Request for [PreviousTrack]")
  local response_map = nil
  if ip then
   local url = format_url(ip, "/UIC?cmd=%3Cname%3ESetTrickMode%3C/name%3E%3Cp%20type=%22str%22%20name=%22trickmode%22%20val=%22previous%22%3E%3C/p%3E")
   ret = handle_http_request(ip, url)
   if ret then
     response_map = { speakerip = ret.handler_res.root.UIC.speakerip,}
   end
  end
  return response_map
end

--- Go to next song for the speaker/speaker group
---
--- @param device table
--- @return err string|nil
function Command.next(ip)
  log.trace("Triggering UPnP Command Request for [NextTrack]")
  local response_map = nil
  if ip then
   local url = format_url(ip, "/UIC?cmd=%3Cname%3ESetTrickMode%3C/name%3E%3Cp%20type=%22str%22%20name=%22trickmode%22%20val=%22next%22%3E%3C/p%3E")
   ret = handle_http_request(ip, url)
   if ret then
     response_map = { speakerip = ret.handler_res.root.UIC.speakerip,}
   end
  end
  return response_map
end

--- Mute the speaker/speaker group
---
--- @param device table
--- @return err string|nil
function Command.mute(ip)
  log.trace("Triggering UPnP Command Request for [mute]")
  local response_map = nil
  if ip then
   local url = format_url(ip, "/UIC?cmd=%3Cname%3ESetMute%3C/name%3E%3Cp%20type=%22str%22%20name=%22mute%22%20val=%22on%22%3E%3C/p%3E")
   ret = handle_http_request(ip, url)
   if ret then
     response_map = { muted = ret.handler_res.root.UIC.response.mute,}
   end
  end
  return response_map
end

--- Unmute the speaker/speaker group
---
--- @param device table
--- @return err string|nil
function Command.unmute(ip)
  log.trace("Triggering UPnP Command Request for [unmute]")
  local response_map = nil
  if ip then
   local url = format_url(ip, "/UIC?cmd=%3Cname%3ESetMute%3C/name%3E%3Cp%20type=%22str%22%20name=%22mute%22%20val=%22off%22%3E%3C/p%3E")
   ret = handle_http_request(ip, url)
   if ret then
     response_map = { muted = ret.handler_res.root.UIC.response.mute,}
   end
  end
  return response_map
end


--- Get Mute Status
---
--- @return err string|nil
function Command.getMute(ip)
  log.trace("Triggering UPnP Command Request for [getMute]")
  local response_map = nil
  if ip then
   local url = format_url(ip, "/UIC?cmd=<name>GetMute</name>")
   ret = handle_http_request(ip, url)
   if ret then
     response_map = { muted = ret.handler_res.root.UIC.response.mute,}
   end
  end
  return response_map
end

--- Get Play Status
---
--- @return err string|nil
function Command.getPlayStatus(ip)
  log.trace("Triggering UPnP Command Request for [getPlayStatus]")
  local response_map = nil
  if ip then
   local url = format_url(ip, "/UIC?cmd=<name>GetPlayStatus</name>")
   ret = handle_http_request(ip, url)
   if ret then
     response_map = { playstatus = ret.handler_res.root.UIC.response.playstatus,}
   end
  end
  return response_map
end


return Command
