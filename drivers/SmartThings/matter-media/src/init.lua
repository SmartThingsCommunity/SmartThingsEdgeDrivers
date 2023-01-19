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

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local MatterDriver = require "st.matter.driver"
local utils = require "st.utils"

local VOLUME_STEP = 5

local function device_init(driver, device)
  device:subscribe()
end

local configure_handler = function(self, device)
  local variable_speed_eps = device:get_endpoints(clusters.MediaPlayback.ID, {feature_bitmap = clusters.MediaPlayback.types.MediaPlaybackFeature.VARIABLE_SPEED})

  if #variable_speed_eps > 0 then
    device:emit_event(capabilities.mediaPlayback.supportedPlaybackCommands({
      capabilities.mediaPlayback.commands.play.NAME,
      capabilities.mediaPlayback.commands.pause.NAME,
      capabilities.mediaPlayback.commands.stop.NAME,
      capabilities.mediaPlayback.commands.rewind.NAME,
      capabilities.mediaPlayback.commands.fastForward.NAME
    }))
  else
    device:emit_event(capabilities.mediaPlayback.supportedPlaybackCommands({
      capabilities.mediaPlayback.commands.play.NAME,
      capabilities.mediaPlayback.commands.pause.NAME,
      capabilities.mediaPlayback.commands.stop.NAME
    }))
  end


  device:emit_event(capabilities.mediaTrackControl.supportedTrackControlCommands({
    capabilities.mediaTrackControl.commands.previousTrack.NAME,
    capabilities.mediaTrackControl.commands.nextTrack.NAME,
  }))

  device:emit_event(capabilities.keypadInput.supportedKeyCodes({
    "UP",
    "DOWN",
    "LEFT",
    "RIGHT",
    "SELECT",
    "BACK",
    "EXIT",
    "MENU",
    "SETTINGS",
    "HOME",
    "NUMBER0",
    "NUMBER1",
    "NUMBER2",
    "NUMBER3",
    "NUMBER4",
    "NUMBER5",
    "NUMBER6",
    "NUMBER7",
    "NUMBER8",
    "NUMBER9",
  }))
end

local function on_off_attr_handler(driver, device, ib, response)
  if device:supports_capability(capabilities.audioMute, device:endpoint_to_component(ib.endpoint_id)) then
    if ib.data.value then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.audioMute.mute.unmuted())
    else
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.audioMute.mute.muted())
    end
  elseif device:supports_capability(capabilities.switch, device:endpoint_to_component(ib.endpoint_id)) then
    if ib.data.value then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switch.switch.on())
    else
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switch.switch.off())
    end
  end
end

local function level_attr_handler(driver, device, ib, response)
  if ib.data.value ~= nil then
    local volume = math.floor((ib.data.value / 254.0 * 100) + 0.5)
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.audioVolume.volume(volume))
  end
end

local function media_playback_state_attr_handler(driver, device, ib, response)
  local CurrentState = clusters.MediaPlayback.attributes.CurrentState
  local attr = capabilities.mediaPlayback.playbackStatus
  local CURRENT_STATE = {
    [CurrentState.PLAYING] = attr.playing(),
    [CurrentState.PAUSED] = attr.paused(),
    [CurrentState.NOT_PLAYING] = attr.stopped(),
    -- TODO: Update to use buffering capability attribute once it is available
    [CurrentState.BUFFERING] = attr.playing()
  }
  if ib.data.value ~= nil then
    device:emit_event_for_endpoint(ib.endpoint_id, CURRENT_STATE[ib.data.value])
  else
    device:emit_event_for_endpoint(ib.endpoint_id, CURRENT_STATE[CurrentState.NOT_PLAYING])
  end
end

local function handle_mute(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local req = clusters.OnOff.server.commands.Off(device, endpoint_id)
  device:send(req)
end

local function handle_unmute(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local req = clusters.OnOff.server.commands.On(device, endpoint_id)
  device:send(req)
end

local function handle_set_mute(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local req
  if cmd.args.state == "muted" then
    req = clusters.OnOff.server.commands.Off(device, endpoint_id)
  else
    req = clusters.OnOff.server.commands.On(device, endpoint_id)
  end
  device:send(req)
end

local function handle_set_volume(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local level = math.floor(cmd.args.volume/100.0 * 254)
  local req = clusters.LevelControl.server.commands.MoveToLevelWithOnOff(device, endpoint_id, level, cmd.args.rate or 0, 0, 0)
  device:send(req)
end

local function handle_volume_up(driver, device, cmd)
  local volume = device:get_latest_state("main", capabilities.audioVolume.ID, capabilities.audioVolume.volume.NAME)
  volume = math.min((volume + VOLUME_STEP), 100)
  cmd.args.volume = volume
  handle_set_volume(driver, device, cmd)
end

local function handle_volume_down(driver, device, cmd)
  local volume = device:get_latest_state("main", capabilities.audioVolume.ID, capabilities.audioVolume.volume.NAME)
  volume = math.max((volume - VOLUME_STEP), 0)
  cmd.args.volume = volume
  handle_set_volume(driver, device, cmd)
end

local command_setter = function(playback_command)
  return function(driver, device, command)
    local endpoint_id = device:component_to_endpoint(command.component)
    local req = playback_command(device, endpoint_id)
    device:send(req)
  end
end

local function handle_send_key(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local KeyCode = clusters.KeypadInput.types.CecKeyCode
  local KEY_MAP = {
    ["UP"] = KeyCode.UP,
    ["DOWN"] = KeyCode.DOWN,
    ["LEFT"] = KeyCode.LEFT,
    ["RIGHT"] = KeyCode.RIGHT,
    ["SELECT"] = KeyCode.SELECT,
    ["BACK"] = KeyCode.BACKWARD,
    ["EXIT"] = KeyCode.EXIT,
    ["MENU"] = KeyCode.CONTENTS_MENU,
    ["SETTINGS"] = KeyCode.SETUP_MENU,
    ["HOME"] = KeyCode.ROOT_MENU,
    ["NUMBER0"] = KeyCode.NUMBER0_OR_NUMBER10,
    ["NUMBER1"] = KeyCode.NUMBERS1,
    ["NUMBER2"] = KeyCode.NUMBERS2,
    ["NUMBER3"] = KeyCode.NUMBERS3,
    ["NUMBER4"] = KeyCode.NUMBERS4,
    ["NUMBER5"] = KeyCode.NUMBERS5,
    ["NUMBER6"] = KeyCode.NUMBERS6,
    ["NUMBER7"] = KeyCode.NUMBERS7,
    ["NUMBER8"] = KeyCode.NUMBERS8,
    ["NUMBER9"] = KeyCode.NUMBERS9,
  }
  local req = clusters.KeypadInput.server.commands.SendKey(device, endpoint_id, KEY_MAP[cmd.args.keyCode])
  device:send(req)
end

local matter_driver_template = {
  lifecycle_handlers = {
    init = device_init,
    doConfigure = configure_handler
  },
  matter_handlers = {
    attr = {
      [clusters.OnOff.ID] = {
        [clusters.OnOff.attributes.OnOff.ID] = on_off_attr_handler,
      },
      [clusters.LevelControl.ID] = {
        [clusters.LevelControl.attributes.CurrentLevel.ID] = level_attr_handler
      },
      [clusters.MediaPlayback.ID] = {
        [clusters.MediaPlayback.attributes.CurrentState.ID] = media_playback_state_attr_handler,
      }
    },
  },
  subscribed_attributes = {
    [capabilities.switch.ID] = {
      clusters.OnOff.attributes.OnOff
    },
    [capabilities.audioMute.ID] = {
      clusters.OnOff.attributes.OnOff
    },
    [capabilities.audioVolume.ID] = {
      clusters.LevelControl.attributes.CurrentLevel
    },
    [capabilities.mediaPlayback.ID] = {
      clusters.MediaPlayback.attributes.CurrentState
    }
  },
  capability_handlers = {
    [capabilities.audioMute.ID] = {
      [capabilities.audioMute.commands.mute.NAME] = handle_mute,
      [capabilities.audioMute.commands.unmute.NAME] = handle_unmute,
      [capabilities.audioMute.commands.setMute.NAME] = handle_set_mute,
    },
    [capabilities.audioVolume.ID] = {
      [capabilities.audioVolume.commands.volumeUp.NAME] = handle_volume_up,
      [capabilities.audioVolume.commands.volumeDown.NAME] = handle_volume_down,
      [capabilities.audioVolume.commands.setVolume.NAME] = handle_set_volume,
    },
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = command_setter(clusters.OnOff.server.commands.On),
      [capabilities.switch.commands.off.NAME] = command_setter(clusters.OnOff.server.commands.Off),
    },
    [capabilities.mediaPlayback.ID] = {
      [capabilities.mediaPlayback.commands.play.NAME] = command_setter(clusters.MediaPlayback.server.commands.Play),
      [capabilities.mediaPlayback.commands.pause.NAME] = command_setter(clusters.MediaPlayback.server.commands.Pause),
      [capabilities.mediaPlayback.commands.stop.NAME] = command_setter(clusters.MediaPlayback.server.commands.StopPlayback),
      [capabilities.mediaPlayback.commands.rewind.NAME] = command_setter(clusters.MediaPlayback.server.commands.Rewind),
      [capabilities.mediaPlayback.commands.fastForward.NAME] = command_setter(clusters.MediaPlayback.server.commands.FastForward),
    },
    [capabilities.mediaTrackControl.ID] = {
      [capabilities.mediaTrackControl.commands.previousTrack.NAME] = command_setter(clusters.MediaPlayback.server.commands.Previous),
      [capabilities.mediaTrackControl.commands.nextTrack.NAME] = command_setter(clusters.MediaPlayback.server.commands.Next),
    },
    [capabilities.keypadInput.ID] = {
      [capabilities.keypadInput.commands.sendKey.NAME] = handle_send_key
    }
  },
  supported_capabilities = {
    capabilities.audioMute,
    capabilities.audioVolume,
    capabilities.switch,
    capabilities.mediaPlayback,
    capabilities.mediaTrackControl,
    capabilities.keypadInput,
  },
}

local matter_driver = MatterDriver("matter-media", matter_driver_template)
matter_driver:run()
