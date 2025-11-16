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
  { mfr = "Samsung Electronics", model = "SAMSUNG-ITM-Z-003" },
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
    device:send(OnOff.server.commands.On(device))
  else
    local speed = device:get_field('LAST_FAN_SPD') or 1
    device:send(FanControl.attributes.FanMode:write(device, speed))
  end
  device:send(FanControl.attributes.FanMode:read(device))
end

local function off_handler(driver, device, command)
  if command.component == 'light' then
    device:send(OnOff.server.commands.Off(device))
  else
    device:send(FanControl.attributes.FanMode:write(device, FanControl.attributes.FanMode.OFF))
  end
  device:send(FanControl.attributes.FanMode:read(device))
end

local function switch_level_handler(driver, device, command)
  local level = math.floor(command.args.level/100.0 * 254)
  device:send(Level.server.commands.MoveToLevelWithOnOff(device, level, command.args.rate or 0xFFFF))
end

local function fan_speed_handler(driver, device, command)
  device:send(FanControl.attributes.FanMode:write(device, command.args.speed))
  device:send(FanControl.attributes.FanMode:read(device))
end

-- ZIGBEE HANDLERS

local function zb_fan_control_handler(driver, device, value, zb_rx)
  device:emit_event(capabilities.fanSpeed.fanSpeed(value.value))
  local evt = capabilities.switch.switch(value.value > 0 and 'on' or 'off', { visibility = { displayed = true } })
  device:emit_component_event(device.profile.components.main, evt)
  device:emit_component_event(device.profile.components.main, capabilities.fanSpeed.fanSpeed(value.value))
  if value.value > 0 then
    device:set_field('LAST_FAN_SPD', value.value, {persist = true})
  end
end

local function zb_level_handler(driver, device, value, zb_rx)
  local evt = capabilities.switchLevel.level(math.floor((value.value / 254.0 * 100) + 0.5))
  device:emit_component_event(device.profile.components.light, evt)
end

local function zb_onoff_handler(driver, device, value, zb_rx)
  local attr = capabilities.switch.switch
  local evt = value.value and attr.on() or attr.off()
  device:emit_component_event(device.profile.components.light, evt)
end

local itm_fan_light = {
  NAME = "ITM Fan Light",
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
  can_handle = can_handle_itm_fanlight
}

return itm_fan_light


