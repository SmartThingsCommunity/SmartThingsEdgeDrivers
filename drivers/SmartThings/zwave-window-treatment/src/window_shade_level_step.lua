-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local st_utils = require "st.utils"
local capabilities = require "st.capabilities"

local utils = {}

-- LATEST_TARGET_LEVEL stores the latest target position during stateless step operations.
-- It is cleared after TARGET_LEVEL_TIME_OUT_SECONDS timeout to allow accumulated steps
-- within a short time frame while preventing indefinite accumulation.
local LATEST_TARGET_LEVEL = "_latestTargetLevel"
-- Timeout in seconds for the stateless step accumulation window
local TARGET_LEVEL_TIME_OUT_SECONDS = 120
-- Field name for the timer that clears LATEST_TARGET_LEVEL after timeout
local TARGET_LEVEL_TIME_OUT = "_targetLevelTimeOut"

-- Step shade level handler for statelessWindowShadeLevelStep capability.
-- The new target is computed on the capability's 0-100 scale and sent through
-- windowShadeLevel.setShadeLevel, so each subdriver's own level handling applies.
utils.step_shade_level_handler = function(driver, device, command)
  local step = command.args.stepSize or 0
  if step == 0 then return end

  -- Step from the latest target level if it exists, or from the current shade level
  local latest_target_level = device:get_field(LATEST_TARGET_LEVEL) or
    device:get_latest_state(command.component, capabilities.windowShadeLevel.ID, capabilities.windowShadeLevel.shadeLevel.NAME, 0)
  local new_target_level = st_utils.clamp_value(latest_target_level + step, 0, 100)

  -- Cancel any previous timer and set a 120 second timeout timer to ensure LATEST_TARGET_LEVEL is cleared
  -- This is to prevent the stateless step from accumulating indefinitely, while ensuring that a single
  -- "scroll" action can accumulate multiple steps within a short time frame
  if device:get_field(TARGET_LEVEL_TIME_OUT) then
    device.thread:cancel_timer(device:get_field(TARGET_LEVEL_TIME_OUT))
  end
  local timer = device.thread:call_with_delay(TARGET_LEVEL_TIME_OUT_SECONDS, function(d)
    device:set_field(LATEST_TARGET_LEVEL, nil)
    -- A completed timer cannot be cancelled, so drop the reference as well
    device:set_field(TARGET_LEVEL_TIME_OUT, nil)
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
