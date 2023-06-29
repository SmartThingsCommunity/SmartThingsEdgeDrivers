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

local log = require "log"
local xml2lua = require "xml2lua"
local xml_handler = require "xmlhandler.tree"
local socket = require "cosock.socket"
local Config = require"lustre".Config
local ws = require"lustre".WebSocket
local CloseCode = require"lustre.frame.close".CloseCode
local capabilities = require "st.capabilities"
local utils = require "st.utils"
local bose_utils = require "utils"
local RECONNECT_PERIOD = 120 -- 2 min

--- @field device table the device the listener is listening for events
--- @field websocket table|nil the websocket connection to the device
--- @module bose.Listener
local Listener = {}
Listener.__index = Listener
Listener.WS_PORT = 8080

function Listener:presets_update(presets)
  log.info(
    string.format("(%s)[%s] presets_update", bose_utils.get_serial_number(self.device), self.device.label))
  self.device:emit_event(capabilities.mediaPresets.presets(presets))
end

function Listener:now_playing_update(info)
  log.info(string.format("(%s)[%s] now playing update %s", bose_utils.get_serial_number(self.device),
                         self.device.label, utils.stringify_table(info)))
  if info.play_state == "INVALID_PLAY_STATUS" then return end
  if info.source == "STANDBY" then
    self.device:emit_event(capabilities.switch.switch.off())
    self.device:emit_event(capabilities.mediaPlayback.playbackStatus.stopped())
  else
    if self.device:get_latest_state("main", capabilities.switch.ID, capabilities.switch.switch.NAME, "off") == "off" then
      self.device:emit_event(capabilities.switch.switch.on())
    end

    -- set play state
    if info.play_state == "STOP_STATE" or info.play_state == "PAUSE_STATE" then
      self.device:emit_event(capabilities.mediaPlayback.playbackStatus.paused())
    else
      self.device:emit_event(capabilities.mediaPlayback.playbackStatus.playing())
    end

    -- get audio track data
    local trackdata = {}
    trackdata.artist = bose_utils.sanitize_field(info.artist)
    trackdata.album = bose_utils.sanitize_field(info.album)
    trackdata.albumArtUrl = bose_utils.sanitize_field(info.art_url)
    trackdata.mediaSource = bose_utils.sanitize_field(info.source)
    trackdata.title = bose_utils.sanitize_field(info.track) or
      bose_utils.sanitize_field(info.station) or
      (info.source == "AUX" and "Auxiliary input") or
      trackdata.mediaSource or "No title"
    self.device:emit_event(capabilities.audioTrackData.audioTrackData(trackdata))
  end
end

--- new preset has been selected
function Listener:preset_select_update(preset_id)
  log.info(string.format("[%s](%s) preset_select_update: %s", bose_utils.get_serial_number(self.device),
                         self.device.label, preset_id))
end

function Listener:volume_update(new_volume, mute_enable)
  log.info(string.format("[%s](%s): volume update %s", bose_utils.get_serial_number(self.device),
                         self.device.label, new_volume))
  self.device:emit_event(capabilities.audioVolume.volume(new_volume))
  if mute_enable then
    self.device:emit_event(capabilities.audioMute.mute.muted())
  else
    self.device:emit_event(capabilities.audioMute.mute.unmuted())
  end
end

-- TODO events not parsed yet
function Listener:zone_update(xml)
  log.info(string.format("[%s](%s) zone_update: %s", bose_utils.get_serial_number(self.device),
                         self.device.label, xml))
end

function Listener:name_update(new_name)
  log.info(string.format("[%s](%s) name_update: %s", bose_utils.get_serial_number(self.device),
                         self.device.label, new_name))
  self.device:try_update_metadata({vendor_provided_label = new_name})
end

function Listener:handle_xml_event(xml)
  local handler = xml_handler:new()
  local xml_parser = xml2lua.parser(handler)
  xml_parser:parse(xml)
  if handler.root.userActivityUpdate then
    return
  elseif handler.root.updates then
    local updates = handler.root.updates
    if updates.volumeUpdated then
      self:volume_update(tonumber(updates.volumeUpdated.volume.actualvolume),
                         updates.volumeUpdated.volume.muteenabled == "true")
    elseif updates.nowPlayingUpdated then
      local art_url
      if updates.nowPlayingUpdated.nowPlaying.art then
        art_url = bose_utils.sanitize_field(updates.nowPlayingUpdated.nowPlaying.art[1])
      end
      self:now_playing_update({
        track = bose_utils.sanitize_field(updates.nowPlayingUpdated.nowPlaying.track),
        artist = bose_utils.sanitize_field(updates.nowPlayingUpdated.nowPlaying.artist),
        album = bose_utils.sanitize_field(updates.nowPlayingUpdated.nowPlaying.album),
        station = bose_utils.sanitize_field(updates.nowPlayingUpdated.nowPlaying.stationName),
        play_state = bose_utils.sanitize_field(updates.nowPlayingUpdated.nowPlaying.playStatus),
        source = bose_utils.sanitize_field(updates.nowPlayingUpdated.nowPlaying._attr.source),
        art_url = bose_utils.sanitize_field(art_url),
      })
    elseif updates.nowSelectionUpdated then
      self:preset_select_update(updates.nowSelectionUpdated.preset._attr.id)
    elseif updates.nameUpdated then
      self:name_update(updates.nameUpdated)
    elseif updates.presetsUpdated and updates.presetsUpdated.presets and
      updates.presetsUpdated.presets.preset then
      local result = {}
      if not updates.presetsUpdated.presets.preset._attr then -- it is a list of presets rather than just one preset
        for _, preset in ipairs(updates.presetsUpdated.presets.preset) do
          if preset._attr and preset._attr.id then
            table.insert(result, {
              id = preset._attr.id, --must exist for valid preset
              name = bose_utils.sanitize_field(preset.ContentItem.itemName, preset._attr.id),
              mediaSource = bose_utils.sanitize_field(preset.ContentItem._attr.source),
              imageUrl = bose_utils.sanitize_field(preset.ContentItem.containerArt),
            })
          end
        end
      elseif updates.presetsUpdated.presets.preset._attr and updates.presetsUpdated.presets.preset._attr.id then
        table.insert(result, {
          id = updates.presetsUpdated.presets.preset._attr.id,
          name = bose_utils.sanitize_field(updates.presetsUpdated.presets.preset.ContentItem.itemName,
            updates.presetsUpdated.presets.preset._attr.id),
          mediaSource = bose_utils.sanitize_field(updates.presetsUpdated.presets.preset.ContentItem._attr.source),
          imageUrl = bose_utils.sanitize_field(updates.presetsUpdated.presets.preset.ContentItem.containerArt),
        })
      else
        log.warn("received invalid presets from device")
      end
      self:presets_update(result)
    else
      log.debug(string.format("[%s](%s) update ignored: %s", bose_utils.get_serial_number(self.device),
                              self.device.label, utils.stringify_table(updates)))
    end
  end
  return handler.root -- used for debugging
end

function Listener:try_reconnect()
  local retries = 0
  local ip = self.device:get_field("ip")
  if not ip then
    log.warn(string.format("[%s](%s) Cannot reconnect because no device ip",
                           bose_utils.get_serial_number(self.device), self.device.label))
    return
  end
  log.info(string.format("[%s](%s) Attempting to reconnect websocket for speaker at %s",
                         bose_utils.get_serial_number(self.device), self.device.label, ip))
  while true do
    if self:start() then
      self.driver:inject_capability_command(self.device,
                                            { capability = capabilities.refresh.ID,
                                              command = capabilities.refresh.commands.refresh.NAME,
                                              args = {}
                                            })
      return
    end
    retries = retries + 1
    log.info(string.format("Reconnect attempt %s in %s seconds", retries, RECONNECT_PERIOD))
    socket.sleep(RECONNECT_PERIOD)
  end
end

--- @return success boolean
function Listener:start()
  local url = "/"
  local sock, err = socket.tcp()
  local ip = self.device:get_field("ip")
  local serial_number = bose_utils.get_serial_number(self.device)
  if not ip then
    log.error_with({hub_logs=true}, "Failed to start listener, no ip address for device")
    return false
  end
  log.info_with({hub_logs=true}, string.format("[%s](%s) Starting websocket listening client on %s:%s",
                         bose_utils.get_serial_number(self.device), self.device.label, ip, url))
  if err then
    log.error_with({hub_logs=true}, string.format("[%s](%s) failed to get tcp socket: %s", serial_number, self.device.label, err))
    return false
  end
  sock:settimeout(3)
  local config = Config.default():protocol("gabbo"):keep_alive(30)
  local websocket = ws.client(sock, "/", config)
  websocket:register_message_cb(function(msg)
    self:handle_xml_event(msg.data)
    -- log.debug(string.format("(%s:%s) Websocket message: %s", device.device_network_id, ip, utils.stringify_table(event, nil, true)))
  end):register_error_cb(function(err)
    -- TODO some muxing on the error conditions
    log.error_with({hub_logs=true}, string.format("[%s](%s) Websocket error: %s", serial_number,
                            self.device.label, err))
    if err and (err:match("closed") or err:match("no response to keep alive ping commands")) then
      self.device:offline()
      self:try_reconnect()
    end
  end)
  websocket:register_close_cb(function(reason)
    log.info_with({hub_logs=true}, string.format("[%s](%s) Websocket closed: %s", serial_number,
                           self.device.label, reason))
    self.websocket = nil -- TODO make sure it is set to nil correctly
    if not self._stopped then self:try_reconnect() end
  end)
  local _
  _, err = websocket:connect(ip, Listener.WS_PORT)
  if err then
    log.error_with({hub_logs=true}, string.format("[%s](%s) failed to connect websocket: %s", serial_number, self.device.label, err))
    return false
  end
  log.info_with({hub_logs=true}, string.format("[%s](%s) Connected websocket successfully", serial_number,
                         self.device.label))
  self._stopped = false
  self.websocket = websocket
  self.device:online()
  return true
end

function Listener.create_device_event_listener(driver, device)
  return setmetatable({device = device, driver = driver, _stopped = true}, Listener)
end

function Listener:stop()
  self._stopped = true
  if not self.websocket then
    log.warn(string.format("[%s](%s) no websocket exists to close", bose_utils.get_serial_number(self.device),
                           self.device.label))
    return
  end
  local suc, err = self.websocket:close(CloseCode.normal())
  if not suc then
    log.error(string.format("[%s](%s) failed to close websocket: %s", bose_utils.get_serial_number(self.device),
                            self.device.label, err))
  end
end

function Listener:is_stopped()
  return self._stopped
end

return Listener
