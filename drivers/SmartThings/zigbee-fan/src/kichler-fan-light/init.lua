-- Copyright 2024 SmartThings
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
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local FanControl = clusters.FanControl
local Level = clusters.Level
local OnOff = clusters.OnOff

local FINGERPRINTS = {
  { mfr = "KICHLER", model = "KICHLER-FANLIGHT-Z-301" },
}

local function can_handle_itm_fanlight(opts, driver, device)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

-- CAPABILITY HANDLERS
local function on_handler(driver, device, command)
  if command.component == 'light' then
    local last_level = device:get_field('LAST_DIM_LEVEL') or 100
    local level = math.floor((last_level/100.0) * 254 )
    device:send_to_component('light', Level.server.commands.MoveToLevelWithOnOff(device, level, command.args.rate or 0xFFFF))
    device:set_field('LAST_DIM_LEVEL', last_level, {persist = true})
  else
    local speed = device:get_field('LAST_FAN_SPD') or 1
    device:send(FanControl.attributes.FanMode:write(device, speed))
  end
  device:send(FanControl.attributes.FanMode:read(device))
end

local function off_handler(driver, device, command)
  if command.component == 'light' then
    local last_level = device:get_field('LAST_DIM_LEVEL') or 100
    device:send_to_component('light', Level.server.commands.MoveToLevelWithOnOff(device, 0, command.args.rate or 0xFFFF))
    device:set_field('LAST_DIM_LEVEL', last_level, {persist = true})
  else
    device:send(FanControl.attributes.FanMode:write(device, FanControl.attributes.FanMode.OFF))
  end
  device:send(FanControl.attributes.FanMode:read(device))
end

local function switch_level_handler(driver, device, command)
  local trim_level = tonumber(device.preferences.trim) or 10
  if command.args.level <= trim_level and command.args.level >= 1 then
    local level = math.floor((trim_level/100.0) * 254 )
    device:emit_component_event(device.profile.components.light, capabilities.switchLevel.level(command.args.level))
    device:send_to_component('light', Level.server.commands.MoveToLevelWithOnOff(device, level, command.args.rate or 0xFFFF))
    device:emit_component_event(device.profile.components.light, capabilities.switchLevel.level(trim_level))
    device:set_field('LAST_DIM_LEVEL', trim_level, {persist = true})
  elseif command.args.level < 1 then
    local level = 0
    device:send_to_component('light', Level.server.commands.MoveToLevelWithOnOff(device, level, command.args.rate or 0xFFFF))
  else
    local level = math.floor((command.args.level/100.0) * 254 )
    device:send_to_component('light', Level.server.commands.MoveToLevelWithOnOff(device, level, command.args.rate or 0xFFFF))
    device:set_field('LAST_DIM_LEVEL', command.args.level, {persist = true})
  end
end

local function fan_speed_handler(driver, device, command)
  if command.args.speed < 4 then
    device:send(FanControl.attributes.FanMode:write(device, command.args.speed))
    device:send(FanControl.attributes.FanMode:read(device))
  end
end

-- ZIGBEE HANDLERS
local function zb_fan_control_handler(driver, device, value, zb_rx)
  if value.value < 4 then
    device:emit_event(capabilities.fanSpeed.fanSpeed(value.value))
    local evt = capabilities.switch.switch(value.value > 0 and 'on' or 'off', { visibility = { displayed = true } })
    device:emit_component_event(device.profile.components.main, evt)
    device:emit_component_event(device.profile.components.main, capabilities.fanSpeed.fanSpeed(value.value))
    if value.value > 0 then
      device:set_field('LAST_FAN_SPD', value.value, {persist = true})
    end
  end
end

local function zb_level_handler(driver, device, value, zb_rx)
  local evt = capabilities.switchLevel.level(math.floor(0.5 + (value.value / 254.0) * 100))
  device:emit_component_event(device.profile.components.light, evt)
end

local function zb_onoff_handler(driver, device, value, zb_rx)
  local attr = capabilities.switch.switch
  local evt = value.value and attr.on() or attr.off()
  device:emit_component_event(device.profile.components.light, evt)
end

local function info_changed(driver, device, event, args)
  if device.preferences ~= nil then
    local current_level = device:get_latest_state('light', capabilities.switchLevel.ID, capabilities.switchLevel.level.NAME) or 100
    local new_trim = tonumber(device.preferences.trim)
    local old_trim = tonumber(args.old_st_store.preferences.trim)
    if args.old_st_store.preferences.trim ~= device.preferences.trim then
      local newlevel = math.floor((current_level/100.0) * 254 )
      if old_trim < new_trim then
        if new_trim >= current_level then
          newlevel = math.floor((new_trim/100.0) * 254 )
        end
      end
      device:send_to_component('light', Level.server.commands.MoveToLevelWithOnOff(device, newlevel, 0))
    end
    if device.preferences.breezemode ~= args.old_st_store.preferences.breezemode then
      local speed = device:get_field('LAST_FAN_SPD') or 1
      local breeze_flag = tonumber(device.preferences.breezemode)
      if breeze_flag == 0 then
        device:send(FanControl.attributes.FanMode:write(device, 5))
        device:send(FanControl.attributes.FanMode:write(device, speed))
      elseif breeze_flag == 1 then
        device:send(FanControl.attributes.FanMode:write(device, 4))
      end
    end
    if device.preferences.fandirection ~= args.old_st_store.preferences.fandirection then
      local send_fandirection_time = device:get_field('FANDIRECTION_SENDTIME') or 0
      local current_fandirection_time = os.time()
      local time_difference = os.difftime(current_fandirection_time, send_fandirection_time) or 0
      if time_difference >= 10 or send_fandirection_time == 0 then
        device:send(FanControl.attributes.FanMode:write(device, 6))
        device:set_field('FANDIRECTION_SENDTIME', current_fandirection_time, {persist = false})
      end
    end
  end
end

local kichler_fan_light = {
  NAME = "KICHLER Fan Light",
  zigbee_handlers = {
    attr = {
      [FanControl.ID] = {
        [FanControl.attributes.FanMode.ID] = zb_fan_control_handler
      },
      [Level.ID] = {
        [Level.attributes.CurrentLevel.ID] = zb_level_handler
      },
      [OnOff.ID] = {
        [OnOff.attributes.OnOff.ID] = zb_onoff_handler
      }
    }
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = on_handler,
      [capabilities.switch.commands.off.NAME] = off_handler,
    },
    [capabilities.switchLevel.ID] = {
      [capabilities.switchLevel.commands.setLevel.NAME] = switch_level_handler
    },
    [capabilities.fanSpeed.ID] = {
      [capabilities.fanSpeed.commands.setFanSpeed.NAME] = fan_speed_handler
    }
    },
    lifecycle_handlers = {
      infoChanged = info_changed
  },
  can_handle = can_handle_itm_fanlight
}

return kichler_fan_light
