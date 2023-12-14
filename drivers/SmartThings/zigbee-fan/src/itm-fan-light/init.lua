-- Copyright 2023 philh30
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

local st_device = require "st.device"
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local FanControl = clusters.FanControl
local Level = clusters.Level
local OnOff = clusters.OnOff

local IFL_FINGERPRINTS = {
  { mfr = "Samsung Electronics", model = "SAMSUNG-ITM-Z-003" },
}

local is_ifl = function(opts, driver, device)
  for _, fingerprint in ipairs(IFL_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

-- Create child device

local function add_child(driver,parent,profile,child_type)
    local child_metadata = {
        type = "EDGE_CHILD",
        label = string.format("%s %s", parent.label, child_type),
        profile = profile,
        parent_device_id = parent.id,
        parent_assigned_child_key = child_type,
        vendor_provided_label = string.format("%s %s", parent.label, child_type)
    }
    driver:try_create_device(child_metadata)
end

local function info_changed(driver, device, event, args)
  if (device.preferences or {}).childLight2 then
    if not device:get_child_by_parent_assigned_key('light') then
        add_child(driver,device,'switch-level','light')
    end
  end
end

-- CAPABILITY HANDLERS

local function on_handler(driver, device, command)
  local dev = device
  if device.network_type == st_device.NETWORK_TYPE_CHILD then
    command.component = 'light'
    dev = device:get_parent_device()
  end
  if command.component == 'light' then
    dev:send(OnOff.server.commands.On(dev))
  else
    local speed = dev:get_field('LAST_FAN_SPD') or 1
    dev:send(FanControl.attributes.FanMode:write(dev,speed))
    dev:send(FanControl.attributes.FanMode:read(dev,speed))
  end
end

local function off_handler(driver, device, command)
  local dev = device
  if device.network_type == st_device.NETWORK_TYPE_CHILD then
    command.component = 'light'
    dev = device:get_parent_device()
  end
  if command.component == 'light' then
    dev:send(OnOff.server.commands.Off(dev))
  else
    dev:send(FanControl.attributes.FanMode:write(dev,FanControl.attributes.FanMode.OFF))
  end
  dev:send(FanControl.attributes.FanMode:read(dev,FanControl.attributes.FanMode.OFF))
end

local function switch_level_handler(driver, device, command)
  local dev = device
  if device.network_type == st_device.NETWORK_TYPE_CHILD then
    command.component = 'light'
    dev = device:get_parent_device()
  end
  if command.component == 'light' then
    local level = math.floor(command.args.level/100.0 * 254)
    dev:send(Level.server.commands.MoveToLevelWithOnOff(dev, level, command.args.rate or 0xFFFF))
  end
end

local function fan_speed_handler(driver, device, command)
  device:send(FanControl.attributes.FanMode:write(device,command.args.speed))
  device:send(FanControl.attributes.FanMode:read(device,command.args.speed))
end

-- ZIGBEE HANDLERS

local function zb_fan_control_handler(driver, device, value, zb_rx)
  device:emit_event(capabilities.fanSpeed.fanSpeed(value.value))
  local evt = capabilities.switch.switch(value.value > 0 and 'on' or 'off', { visibility = { displayed = false } })
  device:emit_component_event(device.profile.components.main,evt)
  if value.value > 0 then
    device:set_field('LAST_FAN_SPD', value.value, {persist = true})
  end
end

local function zb_level_handler(driver, device, value, zb_rx)
  local evt = capabilities.switchLevel.level(math.floor((value.value / 254.0 * 100) + 0.5))
  device:emit_component_event(device.profile.components.light,evt)
  local child = device:get_child_by_parent_assigned_key('light')
  if child ~= nil then
      child:emit_event(evt)
  end
end

local function zb_onoff_handler(driver, device, value, zb_rx)
  local attr = capabilities.switch.switch
  local evt = value.value and attr.on() or attr.off()
  device:emit_component_event(device.profile.components.light,evt)
  local child = device:get_child_by_parent_assigned_key('light')
  if child ~= nil then
      child:emit_event(evt)
  end
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
  lifecycle_handlers = {
    infoChanged = info_changed,
  },
  can_handle = is_ifl
}

return itm_fan_light