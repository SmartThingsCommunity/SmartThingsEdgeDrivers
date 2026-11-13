-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local PowerConfiguration = (require "st.zigbee.zcl.clusters").PowerConfiguration
local capabilities = require "st.capabilities"
local shade_defaults = require "st.zigbee.defaults.windowShade_defaults"
local level_defaults = require "st.zigbee.defaults.windowShadeLevel_defaults"
local shade_utils = require "window_shade_utils"
local position_confirmation = require "zemismart.position_confirmation"
local WindowCovering = (require "st.zigbee.zcl.clusters").WindowCovering
local log = require "log"

local STEP_DISPATCH = "_zemismartStepDispatch"

local function motion_target(device, command)
  if command.capability == capabilities.windowShadeLevel.ID then return command.args.shadeLevel end
  if command.capability == capabilities.windowShadePreset.ID then
    return shade_utils.get_preset_level(device, command.component)
  end
  return command.command == capabilities.windowShade.commands.open.NAME and 100 or 0
end

local function clear_step_target_before(handler)
  return function(driver, device, command)
    local is_step = device:get_field(STEP_DISPATCH)
    local is_pause = command.capability == capabilities.windowShade.ID
      and command.command == capabilities.windowShade.commands.pause.NAME
    if not is_pause and not position_confirmation.position_is_known(device) then
      log.warn_with({ hub_logs = true }, "ZM25Z movement rejected until position is confirmed; reading")
      position_confirmation.start(driver, device, command.component)
      return
    end
    if not is_step then
      shade_utils.clear_step_target(device)
    end
    local ok, result = pcall(handler, driver, device, command)
    if not ok then
      position_confirmation.command_failed(device)
      error(result)
    end
    if is_pause then
      position_confirmation.pause_sent(driver, device)
    else
      position_confirmation.motion_sent(driver, device, motion_target(device, command))
      if not is_step then position_confirmation.start(driver, device, command.component) end
    end
    return result
  end
end

local function step_shade_level_handler(driver, device, command)
  if (command.args.stepSize or 0) == 0 then return end
  if not position_confirmation.position_is_known(device) then
    log.warn_with({ hub_logs = true }, "ZM25Z relative movement requires a confirmed position; reading")
    position_confirmation.start(driver, device, command.component)
    return
  end
  -- SDK injection dispatches synchronously; its internal setShadeLevel belongs
  -- to the same relative-step sequence rather than a new absolute command.
  local previous_dispatch = device:get_field(STEP_DISPATCH)
  device:set_field(STEP_DISPATCH, true)
  local ok, result = pcall(shade_utils.step_shade_level_handler, driver, device, command)
  device:set_field(STEP_DISPATCH, previous_dispatch)
  if not ok then
    shade_utils.clear_step_target(device)
    position_confirmation.command_failed(device)
    error(result)
  end
  position_confirmation.start(driver, device, command.component)
end

-- This externally powered profile has no battery, despite unsolicited battery reports.
local function ignore_battery_report() end

local function init_handler(driver, device)
  -- Preserve the parent driver's preset initialization before establishing volatile trust.
  if device:supports_capability_by_id(capabilities.windowShadePreset.ID)
      and device:get_latest_state("main", "windowShadePreset", "position") == nil then
    device:emit_event(capabilities.windowShadePreset.supportedCommands(
      { "presetPosition", "setPresetPosition" }, { visibility = { displayed = false } }))
    local preset = device:get_field(shade_utils.PRESET_LEVEL_KEY)
      or (device.preferences ~= nil and device.preferences.presetPosition) or shade_utils.PRESET_LEVEL
    device:emit_event(capabilities.windowShadePreset.position(preset,
      { visibility = { displayed = false } }))
    device:set_field(shade_utils.PRESET_LEVEL_KEY, preset, { persist = true })
  end
  position_confirmation.initialize(driver, device)
end

return {
  NAME = "Zemismart window treatment without battery",
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = function(driver, device, command)
        position_confirmation.start(driver, device, command and command.component or "main")
      end,
    },
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
        [PowerConfiguration.attributes.BatteryVoltage.ID] = ignore_battery_report,
        [PowerConfiguration.attributes.BatteryPercentageRemaining.ID] = ignore_battery_report,
      },
      [WindowCovering.ID] = {
        [WindowCovering.attributes.CurrentPositionLiftPercentage.ID] =
          position_confirmation.position_handler,
      },
    },
  },
  lifecycle_handlers = { init = init_handler, removed = position_confirmation.removed },
  can_handle = require("zemismart.can_handle"),
}
