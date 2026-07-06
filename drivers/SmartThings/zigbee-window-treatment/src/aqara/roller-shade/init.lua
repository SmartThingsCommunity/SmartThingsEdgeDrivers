-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local FrameCtrl = require "st.zigbee.zcl.frame_ctrl"
local data_types = require "st.zigbee.data_types"
local aqara_utils = require "aqara/aqara_utils"
local window_treatment_utils = require "window_treatment_utils"
local utils = require "st.utils"

local Basic = clusters.Basic
local WindowCovering = clusters.WindowCovering
local AnalogOutput = clusters.AnalogOutput

local initializedStateWithGuide = capabilities["stse.initializedStateWithGuide"]
local reverseRollerShadeDir = capabilities["stse.reverseRollerShadeDir"]
local shadeRotateState = capabilities["stse.shadeRotateState"]
local setRotateStateCommandName = "setRotateState"

local MULTISTATE_CLUSTER_ID = 0x0013
local MULTISTATE_ATTRIBUTE_ID = 0x0055
local ROTATE_UP_VALUE = 0x0004
local ROTATE_DOWN_VALUE = 0x0005

local LATEST_TARGET_LEVEL = "latest_target_level"
local TARGET_LEVEL_TIME_OUT = "_target_level_timeout"
local TARGET_LEVEL_TIME_OUT_SECONDS = 30

local function window_shade_step_level_cmd(driver, device, command)
  local step = command.args.stepSize or command.args[1]

  local latest_target_level = device:get_field(LATEST_TARGET_LEVEL)
  local current_level = latest_target_level or
    device:get_latest_state("main", capabilities.windowShadeLevel.ID,
      capabilities.windowShadeLevel.shadeLevel.NAME) or 0

  local ui_target_level = current_level + step
  if ui_target_level > 100 then
    ui_target_level = 100
  elseif ui_target_level < 0 then
    ui_target_level = 0
  end
  ui_target_level = utils.round(ui_target_level)

  local device_target_level = 100 - ui_target_level

  device:set_field(LATEST_TARGET_LEVEL, ui_target_level)

  local old_timer = device:get_field(TARGET_LEVEL_TIME_OUT)
  if old_timer ~= nil then
    device.thread:cancel_timer(old_timer)
  end

  local timer = device.thread:call_with_delay(TARGET_LEVEL_TIME_OUT_SECONDS, function(d)
    device:set_field(LATEST_TARGET_LEVEL, nil)
    device:set_field(TARGET_LEVEL_TIME_OUT, nil)
  end)
  device:set_field(TARGET_LEVEL_TIME_OUT, timer)

  device:send_to_component(command.component, WindowCovering.server.commands.GoToLiftPercentage(device, device_target_level))
end

local function window_shade_level_cmd(driver, device, command)
  local initialized = device:get_latest_state("main", initializedStateWithGuide.ID,
    initializedStateWithGuide.initializedStateWithGuide.NAME) or 0
  if initialized ~= initializedStateWithGuide.initializedStateWithGuide.initialized.NAME then
    return
  end

  local level = command.args.shadeLevel
  if level > 100 then
    level = 100
  end
  level = utils.round(level)

  local deviceValue = 100 - level

  device:emit_event(capabilities.windowShadeLevel.shadeLevel(level))
  device:send_to_component(command.component, WindowCovering.server.commands.GoToLiftPercentage(device, deviceValue))
end

local function window_shade_open_cmd(driver, device, command)
  -- Cannot be controlled if not initialized
  local initialized = device:get_latest_state("main", initializedStateWithGuide.ID,
    initializedStateWithGuide.initializedStateWithGuide.NAME) or 0
  if initialized == initializedStateWithGuide.initializedStateWithGuide.initialized.NAME then
    -- Device value 100 = UI open (0% shadeLevel)
    device:send_to_component(command.component, WindowCovering.server.commands.GoToLiftPercentage(device, 100))
  end
end

local function window_shade_close_cmd(driver, device, command)
  -- Cannot be controlled if not initialized
  local initialized = device:get_latest_state("main", initializedStateWithGuide.ID,
    initializedStateWithGuide.initializedStateWithGuide.NAME) or 0
  if initialized == initializedStateWithGuide.initializedStateWithGuide.initialized.NAME then
    -- Device value 0 = UI close (100% shadeLevel)
    device:send_to_component(command.component, WindowCovering.server.commands.GoToLiftPercentage(device, 0))
  end
end

local function set_rotate_command_handler(driver, device, command)
  device:emit_event(shadeRotateState.rotateState.idle({state_change = true, visibility = { displayed = false }})) -- update UI

  -- Cannot be controlled if not initialized
  local initialized = device:get_latest_state("main", initializedStateWithGuide.ID,
    initializedStateWithGuide.initializedStateWithGuide.NAME) or 0
  if initialized == initializedStateWithGuide.initializedStateWithGuide.initialized.NAME then
    local state = command.args.state
    if state == "rotateUp" then
      local message = cluster_base.write_manufacturer_specific_attribute(device, MULTISTATE_CLUSTER_ID,
        MULTISTATE_ATTRIBUTE_ID, aqara_utils.MFG_CODE, data_types.Uint16, ROTATE_UP_VALUE)
      message.body.zcl_header.frame_ctrl = FrameCtrl(0x10)
      device:send(message)
    elseif state == "rotateDown" then
      local message = cluster_base.write_manufacturer_specific_attribute(device, MULTISTATE_CLUSTER_ID,
        MULTISTATE_ATTRIBUTE_ID, aqara_utils.MFG_CODE, data_types.Uint16, ROTATE_DOWN_VALUE)
      message.body.zcl_header.frame_ctrl = FrameCtrl(0x10)
      device:send(message)
    end
  end
end

local function shade_state_report_handler(driver, device, value, zb_rx)
  aqara_utils.emit_shade_event_by_state(device, value)
end

local function shade_level_report_handler(driver, device, value, zb_rx)
  -- Invert the reported value for UI display: device 100% = UI 0% (open), device 0% = UI 100% (close)
  -- AnalogOutput.PresentValue returns SinglePrecisionFloat, extract the numeric value
  local level = value.value
  if level > 100 then
    level = 100
  end
  level = utils.round(level)

  -- Invert: UI value = 100 - device value
  local uiLevel = 100 - level

  -- Update UI shadeLevel
  device:emit_event(capabilities.windowShadeLevel.shadeLevel(uiLevel))

  -- Update UI windowShade state
  if uiLevel >= 100 then
    device:emit_event(capabilities.windowShade.windowShade.closed())
  elseif uiLevel == 0 then
    device:emit_event(capabilities.windowShade.windowShade.open())
  else
    device:emit_event(capabilities.windowShade.windowShade.partially_open())
  end
end

local function pref_report_handler(driver, device, value, zb_rx)
  -- initializedState
  local initialized = string.byte(value.value, 3) & 0xFF
  device:emit_event(initialized == 1 and initializedStateWithGuide.initializedStateWithGuide.initialized() or
    initializedStateWithGuide.initializedStateWithGuide.notInitialized())
end

local function device_info_changed(driver, device, event, args)
  if device.preferences ~= nil then
    local reverseRollerShadeDirPrefValue = device.preferences[reverseRollerShadeDir.ID]
    if reverseRollerShadeDirPrefValue ~= nil and
        reverseRollerShadeDirPrefValue ~= args.old_st_store.preferences[reverseRollerShadeDir.ID] then
      local raw_value = reverseRollerShadeDirPrefValue and aqara_utils.PREF_REVERSE_ON or aqara_utils.PREF_REVERSE_OFF
      device:send(cluster_base.write_manufacturer_specific_attribute(device, Basic.ID, aqara_utils.PREF_ATTRIBUTE_ID,
        aqara_utils.MFG_CODE, data_types.CharString, raw_value))
    end
  end
end

local function device_added(driver, device)
  device:emit_event(capabilities.windowShade.supportedWindowShadeCommands({ "open", "close", "pause" }, {visibility = {displayed = false}}))
  window_treatment_utils.emit_event_if_latest_state_missing(device, "main", capabilities.windowShadeLevel, capabilities.windowShadeLevel.shadeLevel.NAME, capabilities.windowShadeLevel.shadeLevel(0))
  window_treatment_utils.emit_event_if_latest_state_missing(device, "main", capabilities.windowShade, capabilities.windowShade.windowShade.NAME, capabilities.windowShade.windowShade.closed())
  device:emit_event(initializedStateWithGuide.initializedStateWithGuide.notInitialized())
  device:emit_event(shadeRotateState.rotateState.idle({ visibility = { displayed = false }}))

  device:send(cluster_base.write_manufacturer_specific_attribute(device, aqara_utils.PRIVATE_CLUSTER_ID,
    aqara_utils.PRIVATE_ATTRIBUTE_ID, aqara_utils.MFG_CODE, data_types.Uint8, 1))

  -- Initial default settings
  device:send(cluster_base.write_manufacturer_specific_attribute(device, Basic.ID, aqara_utils.PREF_ATTRIBUTE_ID,
    aqara_utils.MFG_CODE, data_types.CharString, aqara_utils.PREF_REVERSE_OFF))
end

local aqara_roller_shade_handler = {
  NAME = "Aqara Roller Shade Handler",
  lifecycle_handlers = {
    added = device_added,
    infoChanged = device_info_changed
  },
  capability_handlers = {
    [capabilities.windowShadeLevel.ID] = {
      [capabilities.windowShadeLevel.commands.setShadeLevel.NAME] = window_shade_level_cmd
    },
    [capabilities.statelessWindowShadeLevelStep.ID] = {
      [capabilities.statelessWindowShadeLevelStep.commands.stepShadeLevel.NAME] = window_shade_step_level_cmd
    },
    [capabilities.windowShade.ID] = {
      [capabilities.windowShade.commands.open.NAME] = window_shade_open_cmd,
      [capabilities.windowShade.commands.close.NAME] = window_shade_close_cmd,
    },
    [shadeRotateState.ID] = {
      [setRotateStateCommandName] = set_rotate_command_handler
    }
  },
  zigbee_handlers = {
    attr = {
      [AnalogOutput.ID] = {
        [AnalogOutput.attributes.PresentValue.ID] = shade_level_report_handler
      },
      [Basic.ID] = {
        [aqara_utils.SHADE_STATE_ATTRIBUTE_ID] = shade_state_report_handler,
        [aqara_utils.PREF_ATTRIBUTE_ID] = pref_report_handler
      }
    }
  },
  can_handle = require("aqara.roller-shade.can_handle"),
}

return aqara_roller_shade_handler
