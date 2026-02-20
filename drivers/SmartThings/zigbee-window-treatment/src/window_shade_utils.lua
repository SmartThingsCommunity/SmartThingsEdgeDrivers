-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local zcl_clusters = require "st.zigbee.zcl.clusters"

local utils = {}

utils.PRESET_LEVEL = 50
utils.PRESET_LEVEL_KEY = "_presetLevel"

utils.get_preset_level = function(device, component)
  local level = device:get_latest_state(component, "windowShadePreset", "position") or
  device:get_field(utils.PRESET_LEVEL_KEY) or
  (device.preferences ~= nil and device.preferences.presetPosition) or
  utils.PRESET_LEVEL

  return level
end

utils.window_shade_preset_cmd = function(driver, device, command)
  local level = device:get_latest_state(command.component, "windowShadePreset", "position") or
    device:get_field(utils.PRESET_LEVEL_KEY) or
    (device.preferences ~= nil and device.preferences.presetPosition) or
    utils.PRESET_LEVEL
  device:send_to_component(command.component, zcl_clusters.WindowCovering.server.commands.GoToLiftPercentage(device, level))
end

utils.set_preset_position_cmd = function(driver, device, command)
  device:emit_component_event({id = command.component}, capabilities.windowShadePreset.position(command.args.position))
  device:set_field(utils.PRESET_LEVEL_KEY, command.args.position, {persist = true})
end

return utils
