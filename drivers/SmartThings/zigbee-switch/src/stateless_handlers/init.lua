-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local st_utils = require "st.utils"
local constants = require "st.zigbee.constants"
local clusters = require "st.zigbee.zcl.clusters"
local switch_utils = require "switch_utils"

-- These values are the mired versions of the config bounds in the default profile (e.g. color-temp-bulb)
local DEFAULT_MIRED_MAX_BOUND = 370 -- 2700 Kelvin (Mireds are the inverse of Kelvin)
local DEFAULT_MIRED_MIN_BOUND = 154 -- 6500 Kelvin (Mireds are the inverse of Kelvin)

-- Transition Time: The time that shall be taken to perform the step change, in units of 1/10ths of a second.
-- Specific fields can store custom transition times for stateless capabilities
local SWITCH_LEVEL_STEP_TRANSITION_TIME = "__switch_level_step_transition_time"
local COLOR_TEMP_STEP_TRANSITION_TIME = "__color_temp_step_transition_time"
local DEFAULT_STEP_TRANSITION_TIME = 3 -- 0.3 seconds

-- Options Mask & Override: Indicates which options are being overridden by the Level/ColorControl cluster commands
local OPTIONS_MASK = 0x01 -- default: The `ExecuteIfOff` option is overriden
local IGNORE_COMMAND_IF_OFF = 0x00 -- default: the command will not be executed if the device is off

-- Indicates whether a delayed refresh for ZLL devices is in progress, to prevent multiple refreshes in a quick series of step commands
local IS_REFRESH_CALLBACK_QUEUED = "__is_refresh_callback_queued"
-- Stores a timer object, which is required to cancel a timer early
local REFRESH_CALLBACK_TIMER = "__refresh_callback_timer"

-- Note: These commands' native handlers do not match the driver's ZLL behavior 1-1.
-- Instead, they will queue a 2s timer and read refresh for each command, in all cases.
local function trigger_delayed_refresh_if_zll(device)
  if device:get_profile_id() ~= constants.ZLL_PROFILE_ID then
    return
  end

  -- If a refresh callback is already queued, cancel it and create a new one with the updated time
  if device:get_field(IS_REFRESH_CALLBACK_QUEUED) then
    device.thread:cancel_timer(device:get_field(REFRESH_CALLBACK_TIMER))
  end
  local delay_s = 2
  local new_timer = device.thread:call_with_delay(delay_s, function()
    device:refresh()
    device:set_field(IS_REFRESH_CALLBACK_QUEUED, nil)
  end)
  device:set_field(REFRESH_CALLBACK_TIMER, new_timer)
  device:set_field(IS_REFRESH_CALLBACK_QUEUED, true)
end

local function step_color_temperature_by_percent_handler(driver, device, cmd)
  if type(device.register_native_capability_cmd_handler) == "function" then
    device:register_native_capability_cmd_handler(cmd.capability, cmd.command)
  end
  local step_percent_change = cmd.args and cmd.args.stepSize or 0
  if step_percent_change == 0 then return end
  local transition_time = device:get_field(COLOR_TEMP_STEP_TRANSITION_TIME) or DEFAULT_STEP_TRANSITION_TIME
  -- Reminder, stepSize > 0 == Kelvin UP == Mireds DOWN. stepSize < 0 == Kelvin DOWN == Mireds UP
  local step_mode = (step_percent_change > 0) and clusters.ColorControl.types.CcStepMode.DOWN or clusters.ColorControl.types.CcStepMode.UP
  -- note: the field containing the color temp bounds will be associated with a parent device
  local field_device = device:get_parent_device() or device
  local min_mireds = field_device:get_field(switch_utils.MIRED_MIN_BOUND)
  local max_mireds = field_device:get_field(switch_utils.MIRED_MAX_BOUND)
  -- since colorTemperatureRange is only set after both custom bounds are, use defaults if any custom bound is missing
  if not (min_mireds and max_mireds) then
    min_mireds = DEFAULT_MIRED_MIN_BOUND
    max_mireds = DEFAULT_MIRED_MAX_BOUND
  end
  local step_size_in_mireds = st_utils.round((max_mireds - min_mireds) * (math.abs(step_percent_change)/100.0))
  device:send(clusters.ColorControl.server.commands.StepColorTemperature(device, step_mode, step_size_in_mireds, transition_time, min_mireds, max_mireds, OPTIONS_MASK, IGNORE_COMMAND_IF_OFF))
  trigger_delayed_refresh_if_zll(device)
end

local function step_level_handler(driver, device, cmd)
  if type(device.register_native_capability_cmd_handler) == "function" then
    device:register_native_capability_cmd_handler(cmd.capability, cmd.command)
  end
  local step_size = st_utils.round((cmd.args and cmd.args.stepSize or 0)/100.0 * 254)
  if step_size == 0 then return end
  local transition_time = device:get_field(SWITCH_LEVEL_STEP_TRANSITION_TIME) or DEFAULT_STEP_TRANSITION_TIME
  local step_mode = (step_size > 0) and clusters.Level.types.MoveStepMode.UP or clusters.Level.types.MoveStepMode.DOWN
  device:send(clusters.Level.server.commands.Step(device, step_mode, math.abs(step_size), transition_time, OPTIONS_MASK, IGNORE_COMMAND_IF_OFF))
  trigger_delayed_refresh_if_zll(device)
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
