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
local http = cosock.asyncify "socket.http" -- TODO use luncheon instead
local log = require "log"
local ltn12 = require "ltn12"
local xml2lua = require "xml2lua"
local xml_handler = require "xmlhandler.tree"
local bose_utils = require "utils"

local SOUNDTOUCH_HTTP_PORT = 8090

--- @module bose.Command
local Command = {}

local function format_url(ip, path)
  return string.format("http://%s:%d%s", ip, SOUNDTOUCH_HTTP_PORT, path)
end

local function handle_http_resp(r, c)
  if not r then
    return string.format("failed http request: %s", c)
  elseif c ~= 200 then
    return string.format("http status: %d", c)
  end
end


--  ===============================================================================================
--  Bose commands to control a speaker or speaker group
--  ===============================================================================================

--- Sends press command mimicking the key on the device
---
--- @param key string
--- @return err string|nil
function Command.key_press(ip, key)
  if not ip then return "no device ip" end
  local press = string.format("<key state=\"press\" sender=\"Gabbo\">%s</key>\n\r", key)
  local url = format_url(ip, "/key")
  local resp = {}
  local r, c, _ = http.request {
    url = url,
    method = "POST",
    headers = {
      ["content-length"] = #press,
      ["host"] = string.format("%s:%d", ip, SOUNDTOUCH_HTTP_PORT),
    },
    sink = ltn12.sink.table(resp),
    source = ltn12.source.string(press),
  }
  return handle_http_resp(r, c)
end

--- Send key release
---
--- @return err string|nil
function Command.key_release(ip, key)
  if not ip then return "no device ip" end
  local release = string.format("<key state=\"release\" sender=\"Gabbo\">%s</key>", key)

  local url = format_url(ip, "/key")
  local resp = {}
  local r, c, _ = http.request {
    url = url,
    method = "POST",
    headers = {
      ["content-length"] = #release,
      ["host"] = string.format("%s:%d", ip, SOUNDTOUCH_HTTP_PORT),
    },
    sink = ltn12.sink.table(resp),
    source = ltn12.source.string(release),
  }
  return handle_http_resp(r, c)
end

--- Gets info on the device
---
--- @return info table
--- @return err string|nil
function Command.info(ip)
  if not ip then return nil, "no device ip" end
  local url = format_url(ip, "/info")
  local resp = {}
  local r, c, _ = http.request {url = url, sink = ltn12.sink.table(resp)}
  local err = handle_http_resp(r, c)
  if err then
    return nil, err
  end

  local handler = xml_handler:new()
  local xml_parser = xml2lua.parser(handler)
  xml_parser:parse(table.concat(resp))
  return {
    name = handler.root.info.name,
    id = handler.root.info._attr.deviceID,
    model = handler.root.info.type,
    ip = handler.root.info.networkInfo[1].ipAddress,
    mac = handler.root.info.networkInfo[1].macAddress,
    account_id = handler.root.info.margeAccountUUID,
  }
end

--- Toggles the speakers power
---
--- @return err string|nil
function Command.toggle_power(ip)
  local err = Command.key_press(ip, "POWER")
  if err then return err end
  return Command.key_release(ip, "POWER")
end

--- Get devices volume level
---
--- @return number between 0 and 100
--- @return err string|nil
function Command.volume(ip)
  if not ip then return nil, "no device ip" end
  local url = format_url(ip, "/volume")
  local resp = {}
  local r, c, _ = http.request {url = url, sink = ltn12.sink.table(resp)}
  local err = handle_http_resp(r, c)
  if err then
    return nil, err
  end

  local handler = xml_handler:new()
  local xml_parser = xml2lua.parser(handler)
  xml_parser:parse(table.concat(resp))
  return {
    actual = tonumber(handler.root.volume.actualvolume),
    target = tonumber(handler.root.volume.targetvolume),
    muted = handler.root.volume.muteenabled == "true",
  }

end

--- Set the speakers volume level
---
--- @param device table
--- @param level number
--- @return err string|nil
function Command.set_volume(ip, level)
  if not ip then return "no device ip" end
  level = math.min(100, math.max(level, 0))
  local volume = string.format("<volume>%d</volume>", level)

  local url = format_url(ip, "/volume")
  local resp = {}
  local r, c, _ = http.request {
    url = url,
    method = "POST",
    headers = {["content-length"] = #volume},
    sink = ltn12.sink.table(resp),
    source = ltn12.source.string(volume),
  }
  return handle_http_resp(r, c)
end

--- Get available sources for the device
---
--- @return table list of source values that can be used with the device
--- @return err string|nil
function Command.sources(ip)
  if not ip then return nil, "no device ip" end
  local url = format_url(ip, "/sources")
  local resp = {}
  local r, c, _ = http.request {url = url, sink = ltn12.sink.table(resp)}
  local err = handle_http_resp(r, c)
  if err then
    return nil, err
  end

  local handler = xml_handler:new()
  local xml_parser = xml2lua.parser(handler)
  xml_parser:parse(table.concat(resp))

  local result = {}
  for _, item in ipairs(handler.root.sources.sourceItem) do
    -- Note: This might not be the correct way to determine the sources available to ST
    if item._attr.status == "READY" then table.insert(result, item._attr.source) end
  end
  return result
end

--- Set the source
---
--- @return err string|nil
function Command.set_source(ip, source)
  -- TODO check for valid source
  if not ip then return "no device ip" end
  local url = format_url(ip, "/select")
  local select = "<ContentItem source=\"AUX\" sourceAccount=\"AUX\"></ContentItem>"
  local resp = {}
  local r, c, _ = http.request {
    url = url,
    method = "POST",
    headers = {["content-length"] = #select},
    sink = ltn12.sink.table(resp),
    source = ltn12.source.string(select),
  }
  return handle_http_resp(r, c)
end

--- Set the devices name
---
--- @return err string|nil
function Command.set_name(ip, name)
  if not ip then return "no device ip" end
  local url = format_url(ip, "/name")
  local set_name = string.format("<name>%s</name>", name)
  local resp = {}
  local r, c, _ = http.request {
    url = url,
    method = "POST",
    headers = {["content-length"] = #set_name},
    sink = ltn12.sink.table(resp),
    source = ltn12.source.string(set_name),
  }
  return handle_http_resp(r, c)
end

--- Play preset on the speaker
---
--- @param device table
--- @param num number preset
--- @return err string|nil
function Command.preset(ip, num)
  if num > 6 then return "invalid preset" end
  -- NOTE: Sending release plays the preset, sending press sets the preset to what is playing
  return Command.key_release(ip, string.format("PRESET_%d", num))
end

--- Play music on the speaker/speaker group
---
--- @param device table
--- @return err string|nil
function Command.play(ip) return Command.key_press(ip, "PLAY") end

--- Pause music on the speaker/speaker group
---
--- @param device table
--- @return err string|nil
function Command.pause(ip) return Command.key_press(ip, "PAUSE") end

--- Go to previous song for the speaker/speaker group
---
--- @param device table
--- @return err string|nil
function Command.previous(ip) return Command.key_press(ip, "PREV_TRACK") end

--- Go to next song for the speaker/speaker group
---
--- @param device table
--- @return err string|nil
function Command.next(ip) return Command.key_press(ip, "NEXT_TRACK") end

--- Mute the speaker/speaker group
---
--- @param device table
--- @return err string|nil
function Command.mute(ip) return Command.key_press(ip, "MUTE") end

--- Unmute the speaker/speaker group
---
--- @param device table
--- @return err string|nil
function Command.unmute(ip) return Command.key_press(ip, "MUTE") end

--- Retreive data on what is currently playing
---
--- @param device table
--- @return info table
--- @return err string|nil
function Command.now_playing(ip)
  if not ip then return nil, "no device ip" end
  local url = format_url(ip, "/now_playing")
  local resp = {}
  local r, c, _ = http.request {url = url, sink = ltn12.sink.table(resp)}
  local err = handle_http_resp(r, c)
  if err then
    return nil, err
  end

  local handler = xml_handler:new()
  local xml_parser = xml2lua.parser(handler)
  xml_parser:parse(table.concat(resp))
  local res = {}
  if handler.root.nowPlaying.art then
    res.art_url = bose_utils.sanitize_field(handler.root.nowPlaying.art[1])
  end
  res.track = bose_utils.sanitize_field(handler.root.nowPlaying.track)
  res.artist = bose_utils.sanitize_field(handler.root.nowPlaying.artist)
  res.album = bose_utils.sanitize_field(handler.root.nowPlaying.album)
  res.station = bose_utils.sanitize_field(handler.root.nowPlaying.stationName)
  res.play_state = bose_utils.sanitize_field(handler.root.nowPlaying.playStatus)
  res.source = bose_utils.sanitize_field(handler.root.nowPlaying._attr.source)
  return res
end

--- Retrieve presets that are set on the device
---
--- @return preset table
--- @return err string|nil
function Command.presets(ip)
  if not ip then return nil, "no device ip" end
  local url = format_url(ip, "/presets")
  local resp = {}
  local r, c, _ = http.request {url = url, sink = ltn12.sink.table(resp)}
  local err = handle_http_resp(r, c)
  if err then
    return nil, err
  end
  local handler = xml_handler:new()
  local xml_parser = xml2lua.parser(handler)
  xml_parser:parse(table.concat(resp))

  local result = {}
  if handler.root.presets.preset then
    if not handler.root.presets.preset._attr then -- it is a list of presets rather than just one preset
      for _, preset in ipairs(handler.root.presets.preset) do
        if preset._attr and preset._attr.id then
          table.insert(result, {
            id = preset._attr.id, --must exist for a valid preset
            name = bose_utils.sanitize_field(preset.ContentItem.itemName, preset._attr.id),
            mediaSource = bose_utils.sanitize_field(preset.ContentItem._attr.source),
            imageUrl = bose_utils.sanitize_field(preset.ContentItem.containerArt),
          })
        end
      end
    elseif handler.root.presets.preset._attr and handler.root.presets.preset._attr.id then
      table.insert(result, {
        id = handler.root.presets.preset._attr.id,
        name = bose_utils.sanitize_field(handler.root.presets.preset.ContentItem.itemName,
          handler.root.presets.preset._attr.id),
        mediaSource = bose_utils.sanitize_field(handler.root.presets.preset.ContentItem._attr.source),
        imageUrl = bose_utils.sanitize_field(handler.root.presets.preset.ContentItem.containerArt),
      })
    else
      log.warn("received invalid presets from device")
    end
  end

  return result
end

--- Retreive zone information for this device.
---
--- @return zone_info table
--- @return err string|nil
function Command.zone_info(ip)
  if not ip then return nil, "no device ip" end
  local url = format_url(ip, "/getZone")
  local resp = {}
  local r, c, _ = http.request {url = url, sink = ltn12.sink.table(resp)}
  local err = handle_http_resp(r, c)
  if err then
    return nil, err
  end

  local handler = xml_handler:new()
  local xml_parser = xml2lua.parser(handler)
  xml_parser:parse(table.concat(resp))
  local members = {}

  if not handler.root.zone.member then return {} end
  -- There aren't zones with only one member
  for _, member in ipairs(handler.root.zone.member) do
    table.insert(members, {
      id = member[1],
      ip = member._attr and member._attr.ipaddress,
    })
  end
  return {master_id = handler.root.zone._attr.master, members = members}
end

--- Play a streaming uri.
---
--- @return err string|nil
function Command.play_streaming_uri(ip, uri, vol)
  if not ip then return nil, "no device ip" end
  local url = format_url(ip, "/speaker")
  local resp = {}
  local app_key = require "app_key"
  if not app_key and not #app_key > 0 then
    local err = "No app_key available to play audio notifications"
    log.error_with({hub_logs = true}, err)
    return err
  end

  local body = string.format("<play_info><app_key>%s</app_key> \
                <url>%s</url> \
                <service>SmartThings</service> \
                <reason>Home Monitor</reason> \
                <message></message> \
                <volume>%d</volume> \
                </play_info>", app_key, uri, vol)

  local r, c, _ = http.request {
    url = url,
    method = "POST",
    headers = {
      ["content-length"] = #body,
      ["host"] = string.format("%s:%d", ip, SOUNDTOUCH_HTTP_PORT),
    },
    sink = ltn12.sink.table(resp),
    source = ltn12.source.string(body),
  }
  return handle_http_resp(r, c)
end

return Command
