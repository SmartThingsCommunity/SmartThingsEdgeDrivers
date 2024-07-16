----------------------------------------------------------
-- Inclusions
----------------------------------------------------------
-- SmartThings inclusions
local Driver = require "st.driver"
local capabilities = require "st.capabilities"
local json = require "st.json"
local log = require "log"
local socket = require "cosock.socket"
local cosock = require "cosock"

-- local Harman Luxury inclusions
local discovery = require "disco"
local hlws = require "hl_websocket"
local api = require "api.apis"
local const = require "constants"

----------------------------------------------------------
-- Device Functions
----------------------------------------------------------

--- handler that builds the JSON to send to the device through the WebSocket
---@param device any
---@param cmd any
local function message_sender(_, device, cmd)
  local msg, value = {}, {}
  local device_ws = device:get_field(const.WEBSOCKET)
  local token = device:get_field(const.CREDENTIAL)

  value[const.CAPABILITY] = cmd.capability or nil
  value[const.COMMAND] = cmd.command or nil
  value[const.ARG] = cmd.args or nil
  msg[const.MESSAGE] = value
  msg[const.CREDENTIAL] = token

  msg = json.encode(msg)

  device_ws:send_msg_handler(msg)
end

--- ensure used presetId is really the Preset ID.
-- When a user sets a preset selection from routines they can insert a custom string.
-- Here we try to guess if the string matches any of the existing presets
local function do_play_preset(_, device, cmd)
  log.info(string.format("Starting do_play_preset: %s", device.label))
  -- send API to play media preset
  local presetId = cmd.args.presetId:lower():gsub("preset", ""):gsub("%W", "")
  local mediaPresets = device:get_latest_state("main", capabilities.mediaPresets.ID,
                                               capabilities.mediaPresets.presets.NAME)
  for _, preset in pairs(mediaPresets) do
    local id = preset.id
    local name = preset.name:lower():gsub("preset", ""):gsub("%W", "")
    if id == presetId or name == presetId then
      cmd.args.presetId = id
      message_sender(_, device, cmd)
      return
    end
  end
  log.warn(string.format("Couldn't find provided Media Preset: %s", cmd.args.presetId))
end

--- checks the health of the websocket connection and triggers the device to send all current values
local function do_refresh(_, device, cmd)
  log.info(string.format("Starting do_refresh: %s", device.label))

  -- restart websocket if needed
  local device_ws = device:get_field(const.WEBSOCKET)
  if device_ws then
    if device_ws.websocket == nil then
      device.log.info("Trying to restart websocket client for device updates")
      device_ws:stop()
      socket.sleep(1) -- give time for Lustre to close the websocket
      if not device_ws:start() then
        log.warn(string.format("%s failed to restart listening websocket client for device updates",
                               device.device_network_id))
        return
      end
    end
    message_sender(_, device, cmd)
  end
end

local function device_init(driver, device)
  log.info(string.format("Initiating device: %s", device.label))

  if device:get_field(const.INITIALISED) then
    log.info(string.format("device_init : already initialized. dni = %s", device.device_network_id))
    return
  end

  local device_dni = device.device_network_id
  if driver.datastore.discovery_cache[device_dni] then
    log.info("set unsaved device field")
    discovery.set_device_field(driver, device)
  end

  -- start websocket
  cosock.spawn(function()
    while true do
      local device_ws = hlws.create_device_websocket(driver, device)
      device:set_field(const.WEBSOCKET, device_ws)
      if device_ws:start() then
        log.info(string.format("%s successfully connected to websocket", device_dni))
        device:set_field(const.INITIALISED, true, {
          persist = false,
        })
        break
      else
        log.info(string.format("%s failed to connect to websocket. Trying again in %d seconds", device_dni,
                               const.WS_RECONNECT_PERIOD))
      end
      socket.sleep(const.WS_RECONNECT_PERIOD)
    end
  end, string.format("%s device_init", device_dni))
end

local function device_removed(_, device)
  local device_dni = device.device_network_id
  log.info(string.format("Device removed - dni=\"%s\"", device_dni))
  -- close websocket
  local device_ws = device:get_field(const.WEBSOCKET)
  if device_ws then
    device_ws:stop()
  end
end

local function device_changeInfo(_, device, _, _)
  log.info(string.format("Device changed info: %s", device.label))
  local ip = device:get_field(const.IP)
  local _, err = api.SetDeviceName(ip, device.label)
  if err then
    log.info(string.format("device_changeInfo: Error occured during attempt to change device name. Error message: %s",
                           err))
  end
end

----------------------------------------------------------
-- Driver Definition
----------------------------------------------------------

--- @type Driver
local driver = Driver("Harman Luxury", {
  discovery = discovery.discovery_handler,
  lifecycle_handlers = {
    added = discovery.device_added,
    init = device_init,
    removed = device_removed,
    infoChanged = device_changeInfo,
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    },
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = message_sender,
      [capabilities.switch.commands.off.NAME] = message_sender,
    },
    [capabilities.audioMute.ID] = {
      [capabilities.audioMute.commands.mute.NAME] = message_sender,
      [capabilities.audioMute.commands.unmute.NAME] = message_sender,
      [capabilities.audioMute.commands.setMute.NAME] = message_sender,
    },
    [capabilities.audioVolume.ID] = {
      [capabilities.audioVolume.commands.volumeUp.NAME] = message_sender,
      [capabilities.audioVolume.commands.volumeDown.NAME] = message_sender,
      [capabilities.audioVolume.commands.setVolume.NAME] = message_sender,
    },
    [capabilities.mediaInputSource.ID] = {
      [capabilities.mediaInputSource.commands.setInputSource.NAME] = message_sender,
    },
    [capabilities.mediaPresets.ID] = {
      [capabilities.mediaPresets.commands.playPreset.NAME] = do_play_preset,
    },
    [capabilities.audioNotification.ID] = {
      [capabilities.audioNotification.commands.playTrack.NAME] = message_sender,
      [capabilities.audioNotification.commands.playTrackAndResume.NAME] = message_sender,
      [capabilities.audioNotification.commands.playTrackAndRestore.NAME] = message_sender,
    },
    [capabilities.mediaPlayback.ID] = {
      [capabilities.mediaPlayback.commands.pause.NAME] = message_sender,
      [capabilities.mediaPlayback.commands.play.NAME] = message_sender,
      [capabilities.mediaPlayback.commands.stop.NAME] = message_sender,
    },
    [capabilities.mediaTrackControl.ID] = {
      [capabilities.mediaTrackControl.commands.nextTrack.NAME] = message_sender,
      [capabilities.mediaTrackControl.commands.previousTrack.NAME] = message_sender,
    },
  },
  supported_capabilities = {capabilities.switch, capabilities.audioMute, capabilities.audioVolume,
                            capabilities.mediaPresets, capabilities.audioNotification, capabilities.mediaPlayback,
                            capabilities.mediaTrackControl, capabilities.refresh},
})

----------------------------------------------------------
-- main
----------------------------------------------------------

-- initialise data store for Harman Luxury driver

if driver.datastore.discovery_cache == nil then
  driver.datastore.discovery_cache = {}
end

-- start driver run loop

log.info("Starting Harman Luxury run loop")
driver:run()
log.info("Exiting Harman Luxury run loop")
