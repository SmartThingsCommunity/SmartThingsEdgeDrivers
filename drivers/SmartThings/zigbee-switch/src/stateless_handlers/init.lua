-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local st_utils = require "st.utils"
local clusters = require "st.zigbee.zcl.clusters"
local constants = require "st.zigbee.constants"

-- Transition Time: The time that shall be taken to perform the step change, in units of 1/10ths of a second.
local TRANSITION_TIME = 3 -- default: 0.3 seconds
-- Options Mask & Override: Indicates which options are being overriden by the Level/ColorControl cluster commands
local OPTIONS_MASK = 0x01 -- default: The `ExecuteIfOff` option is overriden
local IGNORE_COMMAND_IF_OFF = 0x00 -- default: the command will not be executed if the device is off

local function step_color_temperature_by_percent_handler(driver, device, cmd)
    local step_percent_change = cmd.args and cmd.args.stepSize or 0
    if step_percent_change == 0 then return end
    local step_mode = step_percent_change > 0 and (clusters.ColorControl.types.CcStepMode and clusters.ColorControl.types.CcStepMode.DOWN or 3) or (clusters.ColorControl.types.CcStepMode and clusters.ColorControl.types.CcStepMode.UP or 1)
    local min_mireds = device:get_field(constants.KELVIN_MIN) or constants.COLOR_TEMPERATURE_MIRED_MIN -- default min mireds
    local max_mireds = device:get_field(constants.KELVIN_MAX) or constants.COLOR_TEMPERATURE_MIRED_MAX -- default max mireds
    local step_size_in_mireds = st_utils.round((max_mireds - min_mireds) * (math.abs(step_percent_change)/100.0))
    device:send(clusters.ColorControl.server.commands.StepColorTemperature(device, step_mode, step_size_in_mireds, TRANSITION_TIME, min_mireds, max_mireds, OPTIONS_MASK, IGNORE_COMMAND_IF_OFF))
end

local function step_level_handler(driver, device, cmd)
    local step_size = st_utils.round((cmd.args and cmd.args.stepSize or 0)/100.0 * 254)
    if step_size == 0 then return end
    local step_mode = step_size > 0 and clusters.Level.types.MoveStepMode.UP or clusters.Level.types.MoveStepMode.DOWN
    device:send(clusters.Level.server.commands.Step(device, step_mode, math.abs(step_size), TRANSITION_TIME, OPTIONS_MASK, IGNORE_COMMAND_IF_OFF))
end

local stateless_handlers = {
    Name = "Zigbee Stateless Step Handlers",
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
