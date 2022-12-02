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

local command = require "command"
local log = require "log"
local utils = require "st.utils"
local capabilities = require "st.capabilities"

--- @module Samsung-audio.CapabilityHandlers
local CapabilityHandlers = {}

function CapabilityHandlers.handle_on(driver, device, cmd)
  local ip = device:get_field("ip")
  local ret = command.powerOn(ip)
  if ret then
   device:emit_event(capabilities.switch.switch.on())
  end
end

function CapabilityHandlers.handle_off(driver, device, cmd)
  local ip = device:get_field("ip")
  local ret = command.powerOff(ip)
  if ret then
   device:emit_event(capabilities.switch.switch.off())
   device:emit_event(capabilities.mediaPlayback.playbackStatus.stopped())
  end
end

function CapabilityHandlers.handle_play(driver, device, cmd)
  local ip = device:get_field("ip")
  CapabilityHandlers.handle_on(driver, device, nil) --turn on if device is off
  local ret = command.play(ip)
  if ret then
   device:emit_event(capabilities.mediaPlayback.playbackStatus.playing())
  end
end

function CapabilityHandlers.handle_pause(driver, device, cmd)
  local ip = device:get_field("ip")
  local ret = command.pause(ip)
  if ret then
   device:emit_event(capabilities.mediaPlayback.playbackStatus.paused())
  end
end

function CapabilityHandlers.handle_stop(driver, device, cmd)
  local ip = device:get_field("ip")
  local ret = command.pause(ip)
  if ret then
   device:emit_event(capabilities.mediaPlayback.playbackStatus.stopped())
  end
end

function CapabilityHandlers.handle_next_track(driver, device, cmd)
  local ip = device:get_field("ip")
  local ret = command.next(ip)
  if ret then
    device:emit_event(capabilities.mediaPlayback.playbackStatus.playing())
  end
end

function CapabilityHandlers.handle_previous_track(driver, device, cmd)
  local ip = device:get_field("ip")
  local ret = command.previous(ip)
  if ret then
    device:emit_event(capabilities.mediaPlayback.playbackStatus.playing())
  end
end

function CapabilityHandlers.handle_mute(driver, device, cmd)
  local ip = device:get_field("ip")
  command.mute(ip)
end

function CapabilityHandlers.handle_unmute(driver, device, cmd)
  local ip = device:get_field("ip")
  command.unmute(ip)
end

function CapabilityHandlers.handle_volume_up(driver, device, cmd)
  local ip = device:get_field("ip")
  local vol = command.volume(ip)
  if vol then
    command.set_volume(ip, vol.volume + 5)
  end
end

function CapabilityHandlers.handle_volume_down(driver, device, cmd)
  local ip = device:get_field("ip")
  local vol = command.volume(ip)
  if vol then
    command.set_volume(ip, vol.volume - 5)
  end
end

function CapabilityHandlers.handle_set_volume(driver, device, cmd)
  local ip = device:get_field("ip")
  command.set_volume(ip, cmd.args.volume)
end

return CapabilityHandlers
