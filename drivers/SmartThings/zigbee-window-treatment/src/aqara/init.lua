-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local aqara_utils = require "aqara/aqara_utils"
local window_treatment_utils = require "window_treatment_utils"
local utils = require "st.utils"

local Basic = clusters.Basic
local WindowCovering = clusters.WindowCovering
local AnalogOutput = clusters.AnalogOutput
local Groups = clusters.Groups

local deviceInitialization = capabilities["stse.deviceInitialization"]
local reverseCurtainDirection = "stse.reverseCurtainDirection"
local softTouch = "stse.softTouch"
local setInitializedStateCommandName = "setInitializedState"

local INIT_STATE = "initState"
local INIT_STATE_INIT = "init"
local INIT_STATE_OPEN = "open"
local INIT_STATE_CLOSE = "close"
local INIT_STATE_REVERSE = "reverse"
local LATEST_TARGET_LEVEL = "latest_target_level"
local TARGET_LEVEL_TIME_OUT = "_target_level_timeout"
local TARGET_LEVEL_TIME_OUT_SECONDS = 30

local PREF_INITIALIZE = "\x00\x01\x00\x00\x00\x00\x00"
local PREF_SOFT_TOUCH_OFF = "\x00\x08\x00\x00\x00\x01\x00"
local PREF_SOFT_TOUCH_ON = "\x00\x08\x00\x00\x00\x00\x00"

local APPLICATION_VERSION = "application_version"



local function window_shade_level_cmd(driver, device, command)
  aqara_utils.shade_level_cmd(driver, device, command)
end

local function window_shade_step_level_cmd(driver, device, command)
  -- Support both args.stepSize (named) and args[1] (array) formats
  local step = command.args.stepSize or command.args[1]

  -- Priority: use target_level if exists, otherwise use latest state
  -- Note: current_level is the UI display value (already inverted)
  local latest_target_level = device:get_field(LATEST_TARGET_LEVEL)
  local current_level = latest_target_level or
    device:get_latest_state("main", capabilities.windowShadeLevel.ID, capabilities.windowShadeLevel.shadeLevel.NAME) or 0

  -- Calculate UI target_level (user's expected percentage)
  local ui_target_level = current_level + step
  if ui_target_level > 100 then
    ui_target_level = 100
  elseif ui_target_level < 0 then
    ui_target_level = 0
  end
  ui_target_level = utils.round(ui_target_level)

  -- Invert and send to device: device_value = 100 - UI value
  local device_target_level = 100 - ui_target_level

  -- Set target_level for tracking (store UI value)
  device:set_field(LATEST_TARGET_LEVEL, ui_target_level)

  -- Cancel previous timeout timer if exists
  local old_timer = device:get_field(TARGET_LEVEL_TIME_OUT)
  if old_timer ~= nil then
    device.thread:cancel_timer(old_timer)
  end

  -- Set 30 second timeout timer to ensure target_level is cleared
  local timer = device.thread:call_with_delay(TARGET_LEVEL_TIME_OUT_SECONDS, function(d)
    device:set_field(LATEST_TARGET_LEVEL, nil)
    device:set_field(TARGET_LEVEL_TIME_OUT, nil)
  end)
  device:set_field(TARGET_LEVEL_TIME_OUT, timer)

  -- Don't emit to cloud, let device reports drive UI
  -- device:emit_event(capabilities.windowShadeLevel.shadeLevel(ui_target_level))

  -- Send inverted value to device
  device:send_to_component(command.component, WindowCovering.server.commands.GoToLiftPercentage(device, device_target_level))
end

local function set_initialized_state_handler(driver, device, command)
  -- update ui
  device:emit_event(deviceInitialization.initializedState.initializing())

  -- initialize
  device:set_field(INIT_STATE, INIT_STATE_INIT)
  device:send(cluster_base.write_manufacturer_specific_attribute(device, Basic.ID, aqara_utils.PREF_ATTRIBUTE_ID,
    aqara_utils.MFG_CODE, data_types.CharString, PREF_INITIALIZE))

  -- open/close command (invert percentage: 100=closed, 0=open)
  device.thread:call_with_delay(3, function(d)
    local lastLevel = device:get_latest_state("main", capabilities.windowShadeLevel.ID,
      capabilities.windowShadeLevel.shadeLevel.NAME) or 0
    if lastLevel > 0 then
      device:set_field(INIT_STATE, INIT_STATE_CLOSE)
      device:send_to_component(command.component, WindowCovering.server.commands.GoToLiftPercentage(device, 100))
    else
      device:set_field(INIT_STATE, INIT_STATE_OPEN)
      device:send_to_component(command.component, WindowCovering.server.commands.GoToLiftPercentage(device, 0))
    end
  end)
end

local function shade_level_report_legacy_handler(driver, device, value, zb_rx)
  local reported_level = value.value
  local latest_target_level = device:get_field(LATEST_TARGET_LEVEL)

  if latest_target_level then
    -- Active step control
    if utils.round(reported_level) == utils.round(latest_target_level) then
      -- Device reached target position, clear target marker and timeout timer
      device:set_field(LATEST_TARGET_LEVEL, nil)
      local timer = device:get_field(TARGET_LEVEL_TIME_OUT)
      if timer ~= nil then
        device.thread:cancel_timer(timer)
        device:set_field(TARGET_LEVEL_TIME_OUT, nil)
      end
    end
    -- Always emit to update UI with actual device position
  end

  -- for version 34
  aqara_utils.emit_shade_level_event(device, value)
  aqara_utils.emit_shade_event(device, value)
end

local function shade_level_report_handler(driver, device, value, zb_rx)
  local reported_level = value.value
  local latest_target_level = device:get_field(LATEST_TARGET_LEVEL)

  if latest_target_level then
    -- Active step control
    if utils.round(reported_level) == utils.round(latest_target_level) then
      -- Device reached target position, clear target marker and timeout timer
      device:set_field(LATEST_TARGET_LEVEL, nil)
      local timer = device:get_field(TARGET_LEVEL_TIME_OUT)
      if timer ~= nil then
        device.thread:cancel_timer(timer)
        device:set_field(TARGET_LEVEL_TIME_OUT, nil)
      end
    end
    -- Always emit to update UI with actual device position
  end
  aqara_utils.emit_shade_level_event(device, value)
  aqara_utils.emit_shade_event(device, value)
end

local function shade_state_report_handler(driver, device, value, zb_rx)
  aqara_utils.emit_shade_event_by_state(device, value)

  -- initializedState
  local state = value.value
  if state == aqara_utils.SHADE_STATE_STOP or state == 0x04 then
    local init_state_value = device:get_field(INIT_STATE) or ""
    if init_state_value == INIT_STATE_OPEN then
      device:set_field(INIT_STATE, INIT_STATE_REVERSE)
      device.thread:call_with_delay(2, function(d)
        device:send_to_component("main", WindowCovering.server.commands.GoToLiftPercentage(device, 100))
      end)
    elseif init_state_value == INIT_STATE_CLOSE then
      device:set_field(INIT_STATE, INIT_STATE_REVERSE)
      device.thread:call_with_delay(2, function(d)
        device:send_to_component("main", WindowCovering.server.commands.GoToLiftPercentage(device, 0))
      end)
    elseif init_state_value == INIT_STATE_REVERSE then
      device:set_field(INIT_STATE, "")
      device.thread:call_with_delay(2, function(d)
        device:send(cluster_base.read_manufacturer_specific_attribute(device, Basic.ID, aqara_utils.PREF_ATTRIBUTE_ID,
          aqara_utils.MFG_CODE))
      end)
    end
  end
end

local function pref_report_handler(driver, device, value, zb_rx)
  -- initializedState
  local initialized = string.byte(value.value, 3) & 0xFF

  -- Do not update if in progress.
  local init_state_value = device:get_field(INIT_STATE) or ""
  if init_state_value == "" then
    device:emit_event(initialized == 1 and deviceInitialization.initializedState.initialized() or
      deviceInitialization.initializedState.notInitialized())
  end
end

local function application_version_handler(driver, device, value, zb_rx)
  local version = tonumber(value.value)
  device:set_field(APPLICATION_VERSION, version, { persist = true })
end

local function do_refresh(self, device)
  device:send(AnalogOutput.attributes.PresentValue:read(device))
  device:send(cluster_base.read_manufacturer_specific_attribute(device, Basic.ID, aqara_utils.PREF_ATTRIBUTE_ID,
    aqara_utils.MFG_CODE))
end

local function device_info_changed(driver, device, event, args)
  if device.preferences ~= nil then
    local reverseCurtainDirectionPrefValue = device.preferences[reverseCurtainDirection]
    local softTouchPrefValue = device.preferences[softTouch]

    -- reverse direction
    if reverseCurtainDirectionPrefValue ~= nil and
        reverseCurtainDirectionPrefValue ~= args.old_st_store.preferences[reverseCurtainDirection] then
      local raw_value = reverseCurtainDirectionPrefValue and aqara_utils.PREF_REVERSE_ON or aqara_utils.PREF_REVERSE_OFF
      device:send(cluster_base.write_manufacturer_specific_attribute(device, Basic.ID, aqara_utils.PREF_ATTRIBUTE_ID,
        aqara_utils.MFG_CODE, data_types.CharString, raw_value))

      -- read updated value
      device.thread:call_with_delay(2, function(d)
        device:send(cluster_base.read_manufacturer_specific_attribute(device, Basic.ID, aqara_utils.PREF_ATTRIBUTE_ID,
          aqara_utils.MFG_CODE))
      end)
    end

    -- soft touch
    if softTouchPrefValue ~= nil and
        softTouchPrefValue ~= args.old_st_store.preferences[softTouch] then
      local raw_value = softTouchPrefValue and PREF_SOFT_TOUCH_ON or PREF_SOFT_TOUCH_OFF
      device:send(cluster_base.write_manufacturer_specific_attribute(device, Basic.ID, aqara_utils.PREF_ATTRIBUTE_ID,
        aqara_utils.MFG_CODE, data_types.CharString, raw_value))
    end
  end
end

local function do_configure(self, device)
  device:configure()
  device:send(Basic.attributes.ApplicationVersion:read(device))
  device:send(Groups.server.commands.RemoveAllGroups(device))
  do_refresh(self, device)
end

local function device_added(driver, device)
  device:emit_event(capabilities.windowShade.supportedWindowShadeCommands({ "open", "close", "pause" }, {visibility = {displayed = false}}))
  device:emit_event(deviceInitialization.supportedInitializedState({ "notInitialized", "initializing", "initialized" }, {visibility = {displayed = false}}))
  window_treatment_utils.emit_event_if_latest_state_missing(device, "main", capabilities.windowShadeLevel, capabilities.windowShadeLevel.shadeLevel.NAME, capabilities.windowShadeLevel.shadeLevel(0))
  window_treatment_utils.emit_event_if_latest_state_missing(device, "main", capabilities.windowShade, capabilities.windowShade.windowShade.NAME, capabilities.windowShade.windowShade.closed())
  device:emit_event(deviceInitialization.initializedState.notInitialized())

  device:send(cluster_base.write_manufacturer_specific_attribute(device, aqara_utils.PRIVATE_CLUSTER_ID,
    aqara_utils.PRIVATE_ATTRIBUTE_ID, aqara_utils.MFG_CODE, data_types.Uint8, 1))

  -- Initial default settings
  device:send(cluster_base.write_manufacturer_specific_attribute(device, Basic.ID, aqara_utils.PREF_ATTRIBUTE_ID,
    aqara_utils.MFG_CODE, data_types.CharString, aqara_utils.PREF_REVERSE_OFF))
  device:send(cluster_base.write_manufacturer_specific_attribute(device, Basic.ID, aqara_utils.PREF_ATTRIBUTE_ID,
    aqara_utils.MFG_CODE, data_types.CharString, PREF_SOFT_TOUCH_ON))
end

local aqara_window_treatment_handler = {
  NAME = "Aqara Window Treatment Handler",
  lifecycle_handlers = {
    added = device_added,
    doConfigure = do_configure,
    infoChanged = device_info_changed
  },
  capability_handlers = {
    [capabilities.windowShadeLevel.ID] = {
      [capabilities.windowShadeLevel.commands.setShadeLevel.NAME] = window_shade_level_cmd
    },
    [deviceInitialization.ID] = {
      [setInitializedStateCommandName] = set_initialized_state_handler
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    },
    [capabilities.statelessWindowShadeLevelStep.ID] = {
      [capabilities.statelessWindowShadeLevelStep.commands.stepShadeLevel.NAME] = window_shade_step_level_cmd
    }
  },
  zigbee_handlers = {
    attr = {
      [WindowCovering.ID] = {
        [WindowCovering.attributes.CurrentPositionLiftPercentage.ID] = shade_level_report_legacy_handler
      },
      [AnalogOutput.ID] = {
        [AnalogOutput.attributes.PresentValue.ID] = shade_level_report_handler
      },
      [Basic.ID] = {
        [aqara_utils.SHADE_STATE_ATTRIBUTE_ID] = shade_state_report_handler,
        [aqara_utils.PREF_ATTRIBUTE_ID] = pref_report_handler,
        [Basic.attributes.ApplicationVersion.ID] = application_version_handler
      }
    }
  },
  sub_drivers = require("aqara.sub_drivers"),
  can_handle = require("aqara.can_handle"),
}

return aqara_window_treatment_handler
