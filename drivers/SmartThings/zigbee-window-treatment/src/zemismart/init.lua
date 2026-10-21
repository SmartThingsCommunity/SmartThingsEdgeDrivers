-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local PowerConfiguration = (require "st.zigbee.zcl.clusters").PowerConfiguration
local WindowCovering = (require "st.zigbee.zcl.clusters").WindowCovering
local capabilities = require "st.capabilities"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local shade_defaults = require "st.zigbee.defaults.windowShade_defaults"
local level_defaults = require "st.zigbee.defaults.windowShadeLevel_defaults"
local shade_utils = require "window_shade_utils"
local position_recovery = require "zemismart.position_recovery"

local STEP_DISPATCH = "_zemismartStepDispatch"

local function clear_step_target_before(handler)
  return function(driver, device, command)
    position_recovery.cancel(device)
    if not device:get_field(STEP_DISPATCH) then
      shade_utils.clear_step_target(device)
    end
    return handler(driver, device, command)
  end
end

local function step_shade_level_handler(driver, device, command)
  if (command.args.stepSize or 0) == 0 then return end
  -- The injected setShadeLevel is part of this step sequence, not an absolute override.
  local previous_dispatch = device:get_field(STEP_DISPATCH)
  device:set_field(STEP_DISPATCH, true)
  local ok, result = pcall(shade_utils.step_shade_level_handler, driver, device, command)
  device:set_field(STEP_DISPATCH, previous_dispatch)
  if not ok then
    shade_utils.clear_step_target(device)
    error(result)
  end
end

local function battery_handler(handler)
  return function(driver, device, value, zb_rx)
    if device:supports_capability_by_id(capabilities.battery.ID) then
      return handler(driver, device, value, zb_rx)
    end
  end
end

return {
  NAME = "Zemismart window treatment",
  capability_handlers = {
    [capabilities.windowShade.ID] = {
      [capabilities.windowShade.commands.open.NAME] = clear_step_target_before(
        shade_defaults.capability_handlers[capabilities.windowShade.commands.open.NAME]),
      [capabilities.windowShade.commands.close.NAME] = clear_step_target_before(
        shade_defaults.capability_handlers[capabilities.windowShade.commands.close.NAME]),
      [capabilities.windowShade.commands.pause.NAME] = clear_step_target_before(
        shade_defaults.capability_handlers[capabilities.windowShade.commands.pause.NAME]),
    },
    [capabilities.windowShadeLevel.ID] = {
      [capabilities.windowShadeLevel.commands.setShadeLevel.NAME] = clear_step_target_before(
        level_defaults.window_shade_level_cmd),
    },
    [capabilities.windowShadePreset.ID] = {
      [capabilities.windowShadePreset.commands.presetPosition.NAME] = clear_step_target_before(
        shade_utils.window_shade_preset_cmd),
    },
    [capabilities.statelessWindowShadeLevelStep.ID] = {
      [capabilities.statelessWindowShadeLevelStep.commands.stepShadeLevel.NAME] =
        step_shade_level_handler,
    },
  },
  zigbee_handlers = {
    attr = {
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryVoltage.ID] =
          battery_handler(battery_defaults.battery_volt_attr_handler),
        [PowerConfiguration.attributes.BatteryPercentageRemaining.ID] =
          battery_handler(battery_defaults.battery_perc_attr_handler),
      },
      [WindowCovering.ID] = {
        [WindowCovering.attributes.CurrentPositionLiftPercentage.ID] =
          position_recovery.position_handler,
      },
    },
  },
  lifecycle_handlers = {
    removed = function(_, device)
      position_recovery.removed(device)
      shade_utils.clear_step_target(device)
    end,
  },
  can_handle = require("zemismart.can_handle"),
}
