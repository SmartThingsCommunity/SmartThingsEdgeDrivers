-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local st_utils = require "st.utils"
local capabilities = require "st.capabilities"
local zcl_clusters = require "st.zigbee.zcl.clusters"

local utils = {}

utils.PRESET_LEVEL = 50
utils.PRESET_LEVEL_KEY = "_presetLevel"

-- LATEST_TARGET_LEVEL stores the latest target position during stateless step operations.
-- It is cleared after TARGET_LEVEL_TIME_OUT_SECONDS timeout to allow accumulated steps
-- within a short time frame while preventing indefinite accumulation.
local LATEST_TARGET_LEVEL = "_latestTargetLevel"
-- Timeout in seconds for the stateless step accumulation window
local TARGET_LEVEL_TIME_OUT_SECONDS = 15
-- Field name for the timer that clears LATEST_TARGET_LEVEL after timeout
local TARGET_LEVEL_TIME_OUT = "_targetLevelTimeOut"

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

-- Step shade level handler for statelessWindowShadeLevelStep capability
utils.step_shade_level_handler = function(driver, device, command)
  local step = command.args.stepSize or 0
  if step == 0 then return  end

  -- Step from the latest target level if it exists, or from the current shade level
  local latest_target_level = device:get_field(LATEST_TARGET_LEVEL) or
    device:get_latest_state("main", capabilities.windowShadeLevel.ID, capabilities.windowShadeLevel.shadeLevel.NAME, 0)
  local new_target_level = st_utils.clamp_value(latest_target_level + step, 0, 100)

  -- Cancel any previous timer and set a 15 second timeout timer to ensure LATEST_TARGET_LEVEL is cleared
  -- This is to prevent the stateless step from accumulating indefinitely, while ensuring that a single
  -- "scroll" action can accumulate multiple steps within a short time frame
  if device:get_field(TARGET_LEVEL_TIME_OUT) then
    device.thread:cancel_timer(device:get_field(TARGET_LEVEL_TIME_OUT))
  end
  local timer = device.thread:call_with_delay(TARGET_LEVEL_TIME_OUT_SECONDS, function(d)
    device:set_field(LATEST_TARGET_LEVEL, nil)
  end)
  device:set_field(TARGET_LEVEL_TIME_OUT, timer)
  device:set_field(LATEST_TARGET_LEVEL, new_target_level)

  driver:inject_capability_command(device, {
    capability = capabilities.windowShadeLevel.ID,
    component = command.component,
    command = capabilities.windowShadeLevel.commands.setShadeLevel.NAME,
    named_args = { shadeLevel = new_target_level }
  })
end

return utils
