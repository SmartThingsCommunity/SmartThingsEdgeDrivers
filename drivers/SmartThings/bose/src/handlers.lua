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

local command = require "command"
local log = require "log"
local utils = require "st.utils"

--- @module bose.CapabilityHandlers
local CapabilityHandlers = {}

function CapabilityHandlers.handle_on(driver, device, cmd)
  if device.state_cache.main.switch.switch.value == "off" then
    local ip = device:get_field("ip")
    log.info(string.format("[%s](%s) BoseCmd: toggle on {%s}", device.device_network_id,
                           device.label, ip))
    local err = command.toggle_power(ip)
    if err then log.error(string.format("failed to handle power toggle: %s", err)) end
  end
end

function CapabilityHandlers.handle_off(driver, device, cmd)
  if device.state_cache.main.switch.switch.value == "on" then
    local ip = device:get_field("ip")
    log.info(string.format("[%s](%s) BoseCmd: toggle off {%s}", device.device_network_id,
                           device.label, ip))
    local err = command.toggle_power(ip)
    if err then log.error(string.format("failed to handle power toggle: %s", err)) end
  end
end

function CapabilityHandlers.handle_play_preset(driver, device, cmd)
  local ip = device:get_field("ip")
  log.info(string.format("[%s](%s) BoseCmd: play preset %s", device.device_network_id, device.label,
                         cmd.args.presetId))
  local err = command.preset(ip, tonumber(cmd.args.presetId))
  if err then log.error(string.format("failed to handle preset%d: %s", tonumber(cmd.args.presetId), err)) end
end

function CapabilityHandlers.handle_play(driver, device, cmd)
  local ip = device:get_field("ip")
  log.info(string.format("[%s](%s) BoseCmd: play {%s}", device.device_network_id, device.label, ip))
  CapabilityHandlers.handle_on(driver, device, nil) --turn on if device is off
  local err = command.play(ip)
  if err then log.error(string.format("failed to handle play: %s", err)) end
end

function CapabilityHandlers.handle_pause(driver, device, cmd)
  local ip = device:get_field("ip")
  log.info(string.format("[%s](%s) BoseCmd: pause {%s}", device.device_network_id, device.label, ip))
  local err = command.pause(ip)
  if err then log.error(string.format("failed to handle pause: %s", err)) end
end

function CapabilityHandlers.handle_stop(driver, device, cmd)
  local ip = device:get_field("ip")
  log.info(string.format("[%s](%s) BoseCmd: stop (pause) {%s}", device.device_network_id,
                         device.label, ip))
  local err = command.pause(ip)
  if err then log.error(string.format("failed to handle stop: %s", err)) end
end

function CapabilityHandlers.handle_next_track(driver, device, cmd)
  local ip = device:get_field("ip")
  log.info(string.format("[%s](%s) BoseCmd: next track {%s}", device.device_network_id,
                         device.label, ip))
  local err = command.next(ip)
  if err then log.error(string.format("failed to handle next track: %s", err)) end
end

function CapabilityHandlers.handle_previous_track(driver, device, cmd)
  local ip = device:get_field("ip")
  log.info(string.format("[%s](%s) BoseCmd: previous track {%s}", device.device_network_id,
                         device.label, ip))
  local err = command.previous(ip)
  if err then log.error(string.format("failed to handle previous track: %s", err)) end
end

function CapabilityHandlers.handle_mute(driver, device, cmd)
  local ip = device:get_field("ip")
  log.info(string.format("[%s](%s) BoseCmd: mute {%s}", device.device_network_id, device.label, ip))
  local err = command.mute(ip)
  if err then log.error(string.format("failed to handle mute: %s", err)) end
end

function CapabilityHandlers.handle_unmute(driver, device, cmd)
  local ip = device:get_field("ip")
  log.info(
    string.format("[%s](%s) BoseCmd: unmute {%s}", device.device_network_id, device.label, ip))
  local err = command.mute(ip)
  if err then log.error(string.format("failed to handle unmute: %s", err)) end
end

function CapabilityHandlers.handle_set_mute(driver, device, cmd)
  local ip = device:get_field("ip")
  log.info(string.format("[%s](%s) BoseCmd: set mute {%s}", device.device_network_id, device.label,
                         ip))
  local err = command.mute(ip)
  if err then log.error(string.format("failed to handle set mute: %s", err)) end
end

function CapabilityHandlers.handle_volume_up(driver, device, cmd)
  local ip = device:get_field("ip")
  local vol, _ = command.volume(ip)
  if vol then
    log.info(string.format("[%s](%s) BoseCmd: volume up +5 {%s}", device.device_network_id,
                           device.label, ip))
    local err = command.set_volume(ip, vol.actual + 5)
    if err then log.error(string.format("failed to handle volume up: %s", err)) end
  end
end

function CapabilityHandlers.handle_volume_down(driver, device, cmd)
  local ip = device:get_field("ip")
  local vol, _ = command.volume(ip)
  if vol then
    log.info(string.format("[%s](%s) BoseCmd: volume down -5 {%s}", device.device_network_id,
                           device.label, ip))
    local err = command.set_volume(ip, vol.actual - 5)
    if err then log.error(string.format("failed to handle volume down: %s", err)) end
  end
end

function CapabilityHandlers.handle_set_volume(driver, device, cmd)
  local ip = device:get_field("ip")
  log.info(string.format("[%s](%s) BoseCmd: volume set to %d", device.device_network_id,
                         device.label, cmd.args.volume))
  local err = command.set_volume(ip, cmd.args.volume)
  if err then log.error(string.format("failed to handle set volume: %s", err)) end
end

function CapabilityHandlers.handle_audio_notification(driver, device, cmd)
  local ip = device:get_field("ip")
  log.info(string.format("[%s](%s) BoseCmd: audio notification with uri %s at level %d", device.device_network_id,
                         device.label, cmd.args.uri, cmd.args.level))
  local err = command.play_streaming_uri(ip, cmd.args.uri, cmd.args.level)
  if err then log.error(string.format("failed to handle set volume: %s", err)) end
end


return CapabilityHandlers
