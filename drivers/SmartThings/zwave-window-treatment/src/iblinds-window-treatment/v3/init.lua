-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass.SwitchMultilevel
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({ version=3 })

local IBLINDS_WINDOW_TREATMENT_FINGERPRINTS_V3 = {
  {mfr = 0x0287, prod = 0x0004, model = 0x0071}, -- iBlinds Window Treatment v3
  {mfr = 0x0287, prod = 0x0004, model = 0x0072}  -- iBlinds Window Treatment v3
}

--- Determine whether the passed device is iblinds window treatment v3
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @return boolean true if the device is iblinds window treatment, else false
local function can_handle_iblinds_window_treatment_v3(opts, driver, device, ...)
  for _, fingerprint in ipairs(IBLINDS_WINDOW_TREATMENT_FINGERPRINTS_V3) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true
    end
  end
  return false
end

local function init_handler(self, device)
  if device:supports_capability_by_id(capabilities.windowShadePreset.ID) and
    device:get_latest_state("main", capabilities.windowShadePreset.ID, capabilities.windowShadePreset.supportedCommands.NAME) == nil then

    -- setPresetPosition is not supported (device uses a separate preference)
    device:emit_event(capabilities.windowShadePreset.supportedCommands({"presetPosition"}, { visibility = { displayed = false }}))
  end
end

local capability_handlers = {}

function capability_handlers.close(driver, device)
  device:emit_event(capabilities.windowShade.windowShade.closed())
  device:emit_event(capabilities.windowShadeLevel.shadeLevel(0))
  device:send(SwitchMultilevel:Set({value = 0}))
end

local function set_shade_level_helper(driver, device, value)
  value = math.max(math.min(value, 99), 0)
  if value == 0 or value == 99 then
    device:emit_event(capabilities.windowShade.windowShade.closed())
  elseif value == (device.preferences.defaultOnValue or 50) then
    device:emit_event(capabilities.windowShade.windowShade.open())
  else
    device:emit_event(capabilities.windowShade.windowShade.partially_open())
  end
  device:emit_event(capabilities.windowShadeLevel.shadeLevel(value))
  device:send(SwitchMultilevel:Set({value = value}))
end

function capability_handlers.set_shade_level(driver, device, command)
  set_shade_level_helper(driver, device, command.args.shadeLevel)
end

function capability_handlers.preset_position(driver, device)
  set_shade_level_helper(driver, device, device.preferences.defaultOnValue or 50)
end

local iblinds_window_treatment_v3 = {
  lifecycle_handlers = {
    init = init_handler
  },
  capability_handlers = {
    [capabilities.windowShade.ID] = {
      [capabilities.windowShade.commands.close.NAME] = capability_handlers.close
    },
    [capabilities.windowShadeLevel.ID] = {
      [capabilities.windowShadeLevel.commands.setShadeLevel.NAME] = capability_handlers.set_shade_level
    },
    [capabilities.windowShadePreset.ID] = {
      [capabilities.windowShadePreset.commands.presetPosition.NAME] = capability_handlers.preset_position
    }
  },
  NAME = "iBlinds window treatment v3",
  can_handle = can_handle_iblinds_window_treatment_v3
}

return iblinds_window_treatment_v3
