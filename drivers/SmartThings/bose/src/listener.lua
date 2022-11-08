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
local MAX_RECONNECT_ATTEMPTS = 10
local RECONNECT_PERIOD = 120 -- 2 min

--- @field device table the device the listener is listening for events
--- @field websocket table|nil the websocket connection to the device
--- @module bose.Listener
local Listener = {}
Listener.__index = Listener
Listener.WS_PORT = 8080

local function is_empty(t)
  -- empty tables should be nil instead
  return not t or (type(t) == "table" and #t == 0)
end

function Listener:presets_update(presets)
  log.info(
    string.format("(%s)[%s] presets_update", self.device.device_network_id, self.device.label))
  self.device:emit_event(capabilities.mediaPresets.presets(presets))
end

function Listener:now_playing_update(info)
  log.info(string.format("(%s)[%s] now playing update %s", self.device.device_network_id,
                         self.device.label, utils.stringify_table(info)))
  if info.play_state == "INVALID_PLAY_STATUS" then return end
  if info.source == "STANDBY" then
    self.device:emit_event(capabilities.switch.switch.off())
    self.device:emit_event(capabilities.mediaPlayback.playbackStatus.stopped())
  else
    if self.device.state_cache.main.switch.switch.value == "off" then
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
    if not is_empty(info.artist) then trackdata.artist = info.artist end
    if not is_empty(info.album) then trackdata.album = info.album end
    if not is_empty(info.art_url) then trackdata.albumArtUrl = info.art_url end
    if not is_empty(info.source) then
      trackdata.mediaSource = info.source
      -- Note changing supportedTrackControlCommands after join does not seem to take effect in the app immediately.
      -- This indicates a bug in the mobile app.
      if info.source == "TUNEIN" and
        utils.table_size(self.device.state_cache.main.mediaTrackControl.supportedTrackControlCommands.value) > 0 then
        -- Switching to radio source which disables track controls
        self.device:emit_event(capabilities.mediaTrackControl.supportedTrackControlCommands({ }))
      elseif utils.table_size(self.device.state_cache.main.mediaTrackControl.supportedTrackControlCommands.value) == 0 then
        self.device:emit_event(capabilities.mediaTrackControl.supportedTrackControlCommands({
          capabilities.mediaTrackControl.commands.nextTrack.NAME,
          capabilities.mediaTrackControl.commands.previousTrack.NAME,
        }))
      end
    end
    if not is_empty(info.track) then
      trackdata.title = info.track
    elseif not is_empty(info.station) then
      trackdata.title = info.station
    elseif info.source == "AUX" then
      trackdata.title = "Auxilary input"
    end
    self.device:emit_event(capabilities.audioTrackData.audioTrackData(trackdata))
  end
end

--- new preset has been selected
function Listener:preset_select_update(preset_id)
  log.info(string.format("[%s](%s) preset_select_update: %s", self.device.device_network_id,
                         self.device.label, preset_id))
end

function Listener:volume_update(new_volume, mute_enable)
  log.info(string.format("[%s](%s): volume update %s", self.device.device_network_id,
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
  log.info(string.format("[%s](%s) zone_update: %s", self.device.device_network_id,
                         self.device.label, xml))
end

function Listener:name_update(new_name)
  log.info(string.format("[%s](%s) name_update: %s", self.device.device_network_id,
                         self.device.label, new_name))
  local res = self.device:try_update_metadata({vendor_provided_label = new_name})
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
        art_url = updates.nowPlayingUpdated.nowPlaying.art[1]
      end
      self:now_playing_update({
        track = updates.nowPlayingUpdated.nowPlaying.track,
        artist = updates.nowPlayingUpdated.nowPlaying.artist,
        album = updates.nowPlayingUpdated.nowPlaying.album,
        station = updates.nowPlayingUpdated.nowPlaying.stationName,
        play_state = updates.nowPlayingUpdated.nowPlaying.playStatus,
        source = updates.nowPlayingUpdated.nowPlaying._attr.source,
        art_url = art_url,
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
          if is_empty(preset.ContentItem.itemName) then
            preset.ContentItem.itemName = preset._attr.id
          end
          table.insert(result, {
            id = preset._attr.id,
            name = preset.ContentItem.itemName,
            mediaSource = preset.ContentItem._attr.source,
            imageUrl = preset.ContentItem.containerArt,
          })
        end
      else
        if is_empty(updates.presetsUpdated.presets.preset.ContentItem.itemName) then
          updates.presetsUpdated.presets.preset.ContentItem.itemName = updates.presetsUpdated
                                                                         .presets.preset._attr.id
        end
        table.insert(result, {
          id = updates.presetsUpdated.presets.preset._attr.id,
          name = updates.presetsUpdated.presets.preset.ContentItem.itemName,
          mediaSource = updates.presetsUpdated.presets.preset.ContentItem._attr.source,
          imageUrl = updates.presetsUpdated.presets.preset.ContentItem.containerArt,
        })
      end
      self:presets_update(result)
    else
      log.debug(string.format("[%s](%s) update ignored: %s", self.device.device_network_id,
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
                           self.device.device_network_id, self.device.label))
    return
  end
  log.info(string.format("[%s](%s) Attempting to reconnect websocket for speaker at %s",
                         self.device.device_network_id, self.device.label, ip))
  while retries < MAX_RECONNECT_ATTEMPTS do
    if self:start() then
      self.driver:inject_capability_command(self.device,
                                            { capability = capabilities.refresh.ID,
                                              command = capabilities.refresh.commands.refresh.NAME,
                                              args = {}
                                            })
      return
    end
    retries = retries + 1
    log.info(string.format("Retry reconnect in %s seconds", RECONNECT_PERIOD))
    socket.sleep(RECONNECT_PERIOD)
  end
  log.warn(string.format("[%s](%s) failed to reconnect websocket for device events",
                         self.device.device_network_id, self.device.label))
end

--- @return success boolean
function Listener:start()
  local url = "/"
  local sock, err = socket.tcp()
  local ip = self.device:get_field("ip")
  if not ip then
    log.error("failed to get ip address for device")
    return false
  end
  log.info(string.format("[%s](%s) Starting websocket listening client on %s:%s",
                         self.device.device_network_id, self.device.label, ip, url))
  if err then
    log.error(string.format("failed to get tcp socket: %s", err))
    return false
  end
  sock:settimeout(3)
  local config = Config.default():protocol("gabbo"):keep_alive(30)
  local websocket = ws.client(sock, "/", config)
  websocket:register_message_cb(function(msg)
    local event = self:handle_xml_event(msg.data)
    -- log.debug(string.format("(%s:%s) Websocket message: %s", device.device_network_id, ip, utils.stringify_table(event, nil, true)))
  end):register_error_cb(function(err)
    -- TODO some muxing on the error conditions
    log.error(string.format("[%s](%s) Websocket error: %s", self.device.device_network_id,
                            self.device.label, err))
    if err and (err:match("closed") or err:match("no response to keep alive ping commands")) then
      self.device:offline()
      self:try_reconnect()
    end
  end)
  websocket:register_close_cb(function(reason)
    log.info(string.format("[%s](%s) Websocket closed: %s", self.device.device_network_id,
                           self.device.label, reason))
    self.websocket = nil -- TODO make sure it is set to nil correctly
    if not self._stopped then self:try_reconnect() end
  end)
  log.info(string.format("[%s](%s) Connecting websocket to %s", self.device.device_network_id,
                         self.device.label, ip))
  local success, err = websocket:connect(ip, Listener.WS_PORT)
  if err then
    log.error(string.format("failed to connect websocket: %s", err))
    return false
  end
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
    log.warn(string.format("[%s](%s) no websocket exists to close", self.device.device_network_id,
                           self.device.label))
    return
  end
  local suc, err = self.websocket:close(CloseCode.normal())
  if not suc then
    log.error(string.format("[%s](%s) failed to close websocket: %s", self.device.device_network_id,
                            self.device.label, err))
  end
end

return Listener
