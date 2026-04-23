-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local st_utils = require "st.utils"
local clusters = require "st.zigbee.zcl.clusters"
local switch_utils = require "switch_utils"

-- These values are the mired versions of the config bounds in the default profile (e.g. color-temp-bulb)
local DEFAULT_MIRED_MAX_BOUND = 370 -- 2700 Kelvin (Mireds are the inverse of Kelvin)
local DEFAULT_MIRED_MIN_BOUND = 154 -- 6500 Kelvin (Mireds are the inverse of Kelvin)

-- Transition Time: The time that shall be taken to perform the step change, in units of 1/10ths of a second.
local DEFAULT_STATELESS_TRANSITION_TIME = 3 -- 0.3 seconds

-- Options Mask & Override: Indicates which options are being overridden by the Level/ColorControl cluster commands
local OPTIONS_MASK = 0x01 -- default: The `ExecuteIfOff` option is overriden
local IGNORE_COMMAND_IF_OFF = 0x00 -- default: the command will not be executed if the device is off

local function step_color_temperature_by_percent_handler(driver, device, cmd)
  local step_percent_change = cmd.args and cmd.args.stepSize or 0
  if step_percent_change == 0 then return end
  local transition_time = device:get_field(switch_utils.COLOR_TEMP_STEP_TRANSITION_TIME) or DEFAULT_STATELESS_TRANSITION_TIME
  -- Reminder, stepSize > 0 == Kelvin UP == Mireds DOWN. stepSize < 0 == Kelvin DOWN == Mireds UP
  local step_mode = (step_percent_change > 0) and clusters.ColorControl.types.CcStepMode.DOWN or clusters.ColorControl.types.CcStepMode.UP
  local min_mireds = device:get_field(switch_utils.MIRED_MIN_BOUND)
  local max_mireds = device:get_field(switch_utils.MIRED_MAX_BOUND)
  -- since colorTemperatureRange is only set after both custom bounds are, use defaults if any custom bound is missing
  if not (min_mireds and max_mireds) then
    min_mireds = DEFAULT_MIRED_MIN_BOUND
    max_mireds = DEFAULT_MIRED_MAX_BOUND
  end
  local step_size_in_mireds = st_utils.round((max_mireds - min_mireds) * (math.abs(step_percent_change)/100.0))
  device:send(clusters.ColorControl.server.commands.StepColorTemperature(device, step_mode, step_size_in_mireds, transition_time, min_mireds, max_mireds, OPTIONS_MASK, IGNORE_COMMAND_IF_OFF))
end

local function step_level_handler(driver, device, cmd)
  local step_size = st_utils.round((cmd.args and cmd.args.stepSize or 0)/100.0 * 254)
  if step_size == 0 then return end
  local transition_time = device:get_field(switch_utils.SWITCH_LEVEL_STEP_TRANSITION_TIME) or DEFAULT_STATELESS_TRANSITION_TIME
  local step_mode = (step_size > 0) and clusters.Level.types.MoveStepMode.UP or clusters.Level.types.MoveStepMode.DOWN
  device:send(clusters.Level.server.commands.Step(device, step_mode, math.abs(step_size), transition_time, OPTIONS_MASK, IGNORE_COMMAND_IF_OFF))
end

local stateless_handlers = {
  NAME = "Zigbee Stateless Step Handlers",
  capability_handlers = {
    [capabilities.statelessColorTemperatureStep.ID] = {
      [capabilities.statelessColorTemperatureStep.commands.stepColorTemperatureByPercent.NAME] = step_color_temperature_by_percent_handler,
    },
    [capabilities.statelessSwitchLevelStep.ID] = {
      [capabilities.statelessSwitchLevelStep.commands.stepLevel.NAME] = step_level_handler,
    },
  },
  can_handle = require("stateless_handlers.can_handle")
}

return stateless_handlers
