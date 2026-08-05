local log = require "log"

local CloseCode = require "lustre.frame.close".CloseCode
local Config = require "lustre".Config
local ws = require "lustre".WebSocket

local cosock = require "cosock"
local socket = require "cosock.socket"
local capabilities = require "st.capabilities"
local json = require "st.json"
local st_utils = require "st.utils"

local api = require "api.apis"
local const = require "constants"
local discovery = require "disco"

--- a websocket to get updates from Harman Luxury devices
--- @class harman-luxury.HLWebsocket
--- @field driver table the driver the device is a memeber of
--- @field device table the device the websocket is connected to
--- @field websocket table|nil the websocket connection to the device
local HLWebsocket = {}
HLWebsocket.__index = HLWebsocket

--- handles capabilities and sends the commands to the device
---@param msg any device that sends the command
function HLWebsocket:send_msg_handler(msg)
  local dni = self.device.device_network_id
  log.debug(string.format("Sending this message to %s: %s", dni, st_utils.stringify_table(msg)))
  self.websocket:send_text(msg)
end

--- handles listener event messages to update relevant SmartThings capbilities
---@param msg any|table
function HLWebsocket:received_msg_handler(msg)
  if msg[const.CREDENTIAL] then
    -- the device updates all WebSockets when it registers a new credential token. If this hub no longer holds the token
    -- disconnect it
    local currentToken = self.device:get_field(const.CREDENTIAL)
    if msg[const.CREDENTIAL] ~= currentToken then
      local dni = self.device.device_network_id
      log.info(string.format("%s is connected to a different hub. Setting this device offline in this hub", dni))
      self:stop()
      return
    end
  end
  -- check for a power state change
  if msg[capabilities.switch.ID] then
    local powerState = msg[capabilities.switch.ID]
    if powerState == capabilities.switch.commands.on.NAME then
      self.device:emit_event(capabilities.switch.switch.on())
    elseif powerState == capabilities.switch.commands.off.NAME then
      self.device:emit_event(capabilities.switch.switch.off())
    end
  end
  -- check for a player state change
  if msg[capabilities.mediaPlayback.ID] then
    local playerState = msg[capabilities.mediaPlayback.ID]
    if playerState == capabilities.mediaPlayback.commands.play.NAME then
      self.device:emit_event(capabilities.mediaPlayback.playbackStatus.playing())
    elseif playerState == capabilities.mediaPlayback.commands.pause.NAME then
      self.device:emit_event(capabilities.mediaPlayback.playbackStatus.paused())
    else
      self.device:emit_event(capabilities.mediaPlayback.playbackStatus.stopped())
      local stopTrackData = {}
      stopTrackData["title"] = ""
      self.device:emit_event(capabilities.audioTrackData.audioTrackData(stopTrackData))
      self.device:emit_event(capabilities.audioTrackData.totalTime(0))
    end
  end
  -- check for an audio track data change
  if msg[capabilities.audioTrackData.ID] then
    local audioTrackData = msg[capabilities.audioTrackData.ID].audioTrackData
    local totalTime = msg[capabilities.audioTrackData.ID].totalTime
    local trackdata = {}
    if type(audioTrackData.title) == "string" then
      trackdata.title = audioTrackData.title
    else
      trackdata.title = ""
    end
    if type(audioTrackData.artist) == "string" then
      trackdata.artist = audioTrackData.artist
    end
    if type(audioTrackData.album) == "string" then
      trackdata.album = audioTrackData.album
    end
    if type(audioTrackData.albumArtUrl) == "string" then
      trackdata.albumArtUrl = audioTrackData.albumArtUrl
    end
    if type(audioTrackData.mediaSource) == "string" then
      trackdata.mediaSource = audioTrackData.mediaSource
    end
    self.device:emit_event(capabilities.audioTrackData.audioTrackData(trackdata))
    self.device:emit_event(capabilities.audioTrackData.totalTime(totalTime or 0))
  end
  -- check for an elapsed time change
  if msg[capabilities.audioTrackData.elapsedTime.NAME] then
    self.device:emit_event(capabilities.audioTrackData.elapsedTime(msg[capabilities.audioTrackData.ID]))
  end
  -- check for a media presets change
  if msg[capabilities.mediaPresets.ID] and type(msg[capabilities.mediaPresets.ID]) == "table" then
    self.device:emit_event(capabilities.mediaPresets.presets(msg[capabilities.mediaPresets.ID]))
  end
  -- check for a supported input sources change
  if msg["supportedInputSources"] then
    self.device:emit_event(capabilities.mediaInputSource.supportedInputSources(msg["supportedInputSources"]))
  end
  -- check for a supportedInputSources change
  if msg["supportedTrackControlCommands"] then
    self.device:emit_event(capabilities.mediaTrackControl.supportedTrackControlCommands(
                             msg["supportedTrackControlCommands"]) or {})
  end
  -- check for a supported playback commands change
  if msg["supportedPlaybackCommands"] then
    self.device:emit_event(capabilities.mediaPlayback.supportedPlaybackCommands(msg["supportedPlaybackCommands"]) or
                             {})
  end
  -- check for a media input source change
  if msg[capabilities.mediaInputSource.ID] then
    self.device:emit_event(capabilities.mediaInputSource.inputSource(msg[capabilities.mediaInputSource.ID]))
  end
  -- check for a volume value change
  if msg[capabilities.audioVolume.ID] then
    self.device:emit_event(capabilities.audioVolume.volume(msg[capabilities.audioVolume.ID]))
  end
  -- check for a mute value change
  if msg[capabilities.audioMute.ID] ~= nil then
    if msg[capabilities.audioMute.ID] then
      self.device:emit_event(capabilities.audioMute.mute.muted())
    else
      self.device:emit_event(capabilities.audioMute.mute.unmuted())
    end
  end
end

--- socket listener
function HLWebsocket:listener()
  local device_dni = self.device.device_network_id
  while not self._stopped do
    if self.websocket then
      local msg, err
      msg, err = self.websocket:receive()
      if err ~= nil and err ~= "closed" then
        -- unknown error. try reconnect and kill cosock task to avoid more than one listener task for the same device
        log.err(string.format("%s Websocket error: %s", device_dni, err))
        self.device:offline()
        cosock.spawn(self:try_reconnect(), string.format("%s try_reconnect", device_dni))
        return
      elseif err == "closed" then
        -- WebSocket closed. try reconnect and kill cosock task to avoid more than one listener task for the same device
        log.info(string.format("%s Websocket closed: %s", device_dni, err))
        self.websocket = nil
        cosock.spawn(self:try_reconnect(), string.format("%s try_reconnect", device_dni))
        return
      else
        -- handle received message
        log.trace(string.format("%s received websocket message: %s", device_dni, st_utils.stringify_table(msg)))
        local jsonMsg = json.decode(msg.data)
        self:received_msg_handler(jsonMsg)
      end
    else
      cosock.spawn(self:try_reconnect(), string.format("%s try_reconnect", device_dni))
      return
    end
  end
end

--- try reconnect webclient
---@param attempts integer|nil reconnect attempt number (default=0)
---@return boolean has the reconnection succeeded
function HLWebsocket:try_reconnect(attempts)
  attempts = 0 or attempts
  local retries = 0
  local dni = self.device.device_network_id
  local ip = self.device:get_field(const.IP)
  local token = self.device:get_field(const.CREDENTIAL)

  if not ip then
    log.warn(string.format("%s cannot reconnect because no device ip", dni))
    return false
  end

  log.trace(string.format("%s checking if IP are still up to date", dni))
  local activeToken, err = api.GetActiveCredentialToken(ip)
  if err then
    -- device is either offline or changed IP. try to update IP then try reconnect again
    log.warn(string.format("%s error while getting active credential: Error: ", dni, err))
    if attempts < 3 then
      discovery.update_active_devices_ips(self.device)
      return self:try_reconnect(attempts + 1)
    else
      return false
    end
  end

  log.trace(string.format("%s checking if hub is still active", dni))
  if token ~= activeToken then
    -- hub no longer active. stop device onn this hub
    self:stop()
    return false
  end

  log.info(string.format("%s attempting to reconnect websocket for speaker at %s", dni, ip))
  while true do
    if self:start() then
      return true
    end
    retries = retries + 1
    log.info(string.format("Reconnect attempt %s in %s seconds", retries, const.WS_RECONNECT_PERIOD))
    socket.sleep(const.WS_RECONNECT_PERIOD)
  end
end

--- functionto start the websocket connection
--- @return boolean boolean
function HLWebsocket:start()
  local dni = self.device.device_network_id
  local ip = self.device:get_field(const.IP)
  if not ip then
    log.error(string.format("Failed to start %s websocket connection, no ip address for device", dni))
    return false
  end

  log.info(string.format("%s starting websocket client on %s", dni, ip))
  local sock, err = socket.tcp()
  if not sock or err ~= nil then
    log.error(string.format("%s Could not open TCP socket: %s", dni, err))
    return false
  end

  local _
  _, err = sock:settimeout(const.WS_SOCKET_TIMEOUT)
  if err ~= nil then
    log.warn(string.format("%s Socket set timeout error: %s", dni, err))
    return false
  end

  local config = Config.default():keep_alive(const.WS_IDLE_PING_PERIOD)
  local websocket = ws.client(sock, "/", config)
  _, err = websocket:connect(ip, const.WS_PORT)
  if err then
    log.error(string.format("%s failed to connect websocket: %s", dni, err))
    self.device:offline()
    return false
  end

  log.info(string.format("%s Connected websocket successfully", dni))
  self._stopped = false
  self.websocket = websocket
  self.device:online()

  log.trace(string.format("%s Refreshing all values after successful WebSocket connection", dni))
  self.driver:inject_capability_command(self.device, {
    capability = capabilities.refresh.ID,
    command = capabilities.refresh.commands.refresh.NAME,
    args = {},
  })

  log.trace(string.format("%s Started websocket listener", dni))
  cosock.spawn(self:listener(), string.format("%s listener", dni))

  return true
end

--- creates a Harman Luxury websocket object for the device
---@param driver any
---@param device any
---@return HLWebsocket
function HLWebsocket.create_device_websocket(driver, device)
  return setmetatable({
    device = device,
    driver = driver,
    _stopped = true,
  }, HLWebsocket)
end

--- stops webclient
function HLWebsocket:stop()
  local dni = self.device.device_network_id
  self.device:offline()
  self._stopped = true
  if not self.websocket then
    log.warn(string.format("%s no websocket exists to close", dni))
    return
  end
  local suc, err = self.websocket:close(CloseCode.normal())
  if not suc then
    log.error(string.format("%s failed to close websocket: %s", dni, err))
  end
end

--- tests if the websocket connection is stopped or not
--- @return boolean isStopped
function HLWebsocket:is_stopped()
  return self._stopped
end

return HLWebsocket
