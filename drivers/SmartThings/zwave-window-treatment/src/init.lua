-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
--- @type st.zwave.defaults
local defaults = require "st.zwave.defaults"
--- @type st.zwave.Driver
local ZwaveDriver = require "st.zwave.driver"
--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=4 })
local preferencesMap = require "preferences"
local window_preset_defaults = require "window_preset_defaults"

local function init_handler(self, device)
  if device:supports_capability_by_id(capabilities.windowShadePreset.ID) and
    device:get_latest_state("main", capabilities.windowShadePreset.ID, capabilities.windowShadePreset.position.NAME) == nil then

    -- These should only ever be nil once (and at the same time) for already-installed devices
    -- It can be relocated to `added` after migration is complete
    device:emit_event(capabilities.windowShadePreset.supportedCommands({"presetPosition", "setPresetPosition"}, { visibility = { displayed = false }}))

    local preset_position = device:get_field(window_preset_defaults.PRESET_LEVEL_KEY) or
      (device.preferences ~= nil and device.preferences.presetPosition) or
      window_preset_defaults.PRESET_LEVEL

    device:emit_event(capabilities.windowShadePreset.position(preset_position, { visibility = {displayed = false}}))
    device:set_field(window_preset_defaults.PRESET_LEVEL_KEY, preset_position, {persist = true})
  end
end

local function added_handler(self, device)
  device:emit_event(capabilities.windowShade.supportedWindowShadeCommands({"open", "close", "pause"}, { visibility = { displayed = false } }))
end

--- Handle preference changes
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @param event table
--- @param args
local function info_changed(driver, device, event, args)
  local preferences = preferencesMap.get_device_parameters(device)
  if preferences then
    for id, value in pairs(device.preferences) do
      if preferences[id] and args.old_st_store.preferences[id] ~= value then
        local new_parameter_value = preferencesMap.to_numeric_value(device.preferences[id])
        device:send(Configuration:Set({parameter_number = preferences[id].parameter_number, size = preferences[id].size, configuration_value = new_parameter_value}))
      end
    end
  end
end

--------------------------------------------------------------------------------------------
-- Register message handlers and run driver
--------------------------------------------------------------------------------------------

local driver_template = {
  supported_capabilities = {
    capabilities.windowShade,
    capabilities.windowShadeLevel,
    capabilities.windowShadePreset,
    capabilities.statelessCurtainPowerButton,
    capabilities.battery
  },
  lifecycle_handlers = {
    init = init_handler,
    added = added_handler,
    infoChanged = info_changed
  },
  capability_handlers = {
    [capabilities.windowShadePreset.ID] = {
      [capabilities.windowShadePreset.commands.setPresetPosition.NAME] = window_preset_defaults.set_preset_position_cmd,
      [capabilities.windowShadePreset.commands.presetPosition.NAME] = window_preset_defaults.window_shade_preset_cmd,
    }
  },
  sub_drivers = require("sub_drivers"),
}

defaults.register_for_default_handlers(driver_template, driver_template.supported_capabilities)
--- @type st.zwave.Driver
local window_treatment = ZwaveDriver("zwave_window_treatment", driver_template)
window_treatment:run()
