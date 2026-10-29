-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass.SwitchMultilevel
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({ version=3 })
local window_preset_defaults = require "window_preset_defaults"


--- Determine whether the passed device is iblinds window treatment
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @return boolean true if the device is iblinds window treatment, else false

local capability_handlers = {}

-- The device receives the reversed level when reverse is set; state always holds the level the user asked for
local function device_level(device, value)
  return device.preferences.reverse and 99 - value or value
end

local function send_shade_level(device, value)
  device:emit_event(capabilities.windowShadeLevel.shadeLevel(value))
  device:send(SwitchMultilevel:Set({value = device_level(device, value)}))
end

function capability_handlers.open(driver, device)
  local value = device.preferences.defaultOnValue or 50
  device:emit_event(capabilities.windowShade.windowShade.open())
  send_shade_level(device, value)
end

function capability_handlers.close(driver, device)
  device:emit_event(capabilities.windowShade.windowShade.closed())
  send_shade_level(device, 0)
end

local function set_shade_level_helper(driver, device, value)
  value = math.max(math.min(value, 99), 0)
  local device_value = device_level(device, value)
  if device_value == 0 or device_value == 99 then
    device:emit_event(capabilities.windowShade.windowShade.closed())
  elseif device_value == 50 then
    device:emit_event(capabilities.windowShade.windowShade.open())
  else
    device:emit_event(capabilities.windowShade.windowShade.partially_open())
  end
  send_shade_level(device, value)
end

function capability_handlers.set_shade_level(driver, device, command)
  set_shade_level_helper(driver, device, command.args.shadeLevel)
end

function capability_handlers.preset_position(driver, device, command)
  local level = device:get_latest_state(command.component, "windowShadePreset", "position") or
    device:get_field(window_preset_defaults.PRESET_LEVEL_KEY) or
    (device.preferences ~= nil and device.preferences.presetPosition) or 50
  set_shade_level_helper(driver, device, level)
end

local iblinds_window_treatment = {
  capability_handlers = {
    [capabilities.windowShade.ID] = {
      [capabilities.windowShade.commands.open.NAME] = capability_handlers.open,
      [capabilities.windowShade.commands.close.NAME] = capability_handlers.close
    },
    [capabilities.windowShadeLevel.ID] = {
      [capabilities.windowShadeLevel.commands.setShadeLevel.NAME] = capability_handlers.set_shade_level
    },
    [capabilities.windowShadePreset.ID] = {
      [capabilities.windowShadePreset.commands.presetPosition.NAME] = capability_handlers.preset_position
    }
  },
  sub_drivers = require("iblinds-window-treatment.sub_drivers"),
  NAME = "iBlinds window treatment",
  can_handle = require("iblinds-window-treatment.can_handle"),
}

return iblinds_window_treatment
