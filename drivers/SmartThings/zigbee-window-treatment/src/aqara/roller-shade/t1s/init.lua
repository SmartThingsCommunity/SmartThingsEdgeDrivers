-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local FrameCtrl = require "st.zigbee.zcl.frame_ctrl"
local data_types = require "st.zigbee.data_types"
local aqara_utils = require "aqara/aqara_utils"
local window_treatment_utils = require "window_treatment_utils"
local utils = require "st.utils"

local Groups = clusters.Groups
local WindowCovering = clusters.WindowCovering
local AnalogOutput = clusters.AnalogOutput

local initializedStateWithGuide = capabilities["stse.initializedStateWithGuide"]
local reverseRollerShadeDir = capabilities["stse.reverseRollerShadeDir"]
local shadeRotateState = capabilities["stse.shadeRotateState"]
local setRotateStateCommandName = "setRotateState"
local directionReversal = "directionReversal"

local MULTISTATE_CLUSTER_ID = 0x0013
local MULTISTATE_ATTRIBUTE_ID = 0x0055
local INIT_STATE_ATTRIBUTE_ID = 0x0407
local DIRECTION_ATTRIBUTE_ID = 0x0400

local ROTATE_UP_VALUE = 0x0006
local ROTATE_DOWN_VALUE = 0x0005
local SHADE_STATE_STOP = 2
local SHADE_STATE_OPEN = 1
local SHADE_STATE_CLOSE = 0
local SHADE_STATE_BLOCKED = 4

local INIT_STATE_REPORTED = "initStateReported"

local function is_not_init(device)
  if not device:get_field(INIT_STATE_REPORTED) then return false end

  -- True if uninitialized; false if already initialized
  local initialized = device:get_latest_state("main", initializedStateWithGuide.ID,
    initializedStateWithGuide.initializedStateWithGuide.NAME) or 0
  local ret = true
  if initialized == initializedStateWithGuide.initializedStateWithGuide.initialized.NAME then ret = false end
  return ret
end


local function window_shade_level_cmd(driver, device, command)
  -- Cannot be controlled if not initialized
  if is_not_init(device) then return end
  local level = command.args.shadeLevel > 100 and 100 or utils.round(command.args.shadeLevel)
  device:emit_event(capabilities.windowShadeLevel.shadeLevel(level))
  device:send_to_component(command.component, WindowCovering.server.commands.GoToLiftPercentage(device, level))
end

local function window_shade_open_cmd(driver, device, command)
  -- Cannot be controlled if not initialized
  if is_not_init(device) then return end
  device:send_to_component(command.component, WindowCovering.server.commands.GoToLiftPercentage(device, 100))
end

local function window_shade_close_cmd(driver, device, command)
  -- Cannot be controlled if not initialized
  if is_not_init(device) then return end
  device:send_to_component(command.component, WindowCovering.server.commands.GoToLiftPercentage(device, 0))
end

local function set_rotate_command_handler(driver, device, command)
  device:emit_event(shadeRotateState.rotateState.idle({ state_change = true, visibility = { displayed = false } })) -- update UI

  -- Cannot be controlled if not initialized
  if is_not_init(device) then return end
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

local function do_refresh(driver, device)
  device:send(AnalogOutput.attributes.PresentValue:read(device))
  device:send(cluster_base.read_manufacturer_specific_attribute(device, aqara_utils.PRIVATE_CLUSTER_ID, INIT_STATE_ATTRIBUTE_ID, aqara_utils.MFG_CODE))
end

local function init_state_handler(driver, device, value, zb_rx)
  device:set_field(INIT_STATE_REPORTED, true, { persist = true })
  local state = value.value == 0x02 and initializedStateWithGuide.initializedStateWithGuide.initialized() or
  initializedStateWithGuide.initializedStateWithGuide.notInitialized()
  device:emit_event(state)
end

local function shade_level_report_handler(driver, device, value, zb_rx)
  local level = value.value > 100 and 100 or utils.round(value.value)
  device:emit_event(capabilities.windowShadeLevel.shadeLevel(level))
  if level >= 100 then
    device:emit_event(capabilities.windowShade.windowShade.open())
  elseif level <= 0 then
    device:emit_event(capabilities.windowShade.windowShade.closed())
  else
    device:emit_event(capabilities.windowShade.windowShade.partially_open())
  end
end

-- The position of this device is reported through the present value of the analog output
-- cluster, where 0 is fully closed and 100 is fully open. The lift percentage of the window
-- covering cluster is reported with the opposite polarity (100% = fully closed), so it is
-- ignored here to keep the parent Aqara handler from emitting an inverted shade level.
local function current_position_lift_percentage_handler(driver, device, value, zb_rx)
end

local function shade_state_report_handler(driver, device, value, zb_rx)
  local state = value.value
  -- update state ui
  if state == SHADE_STATE_STOP or state == SHADE_STATE_BLOCKED then
    -- read shade position to update the UI
    device:send(AnalogOutput.attributes.PresentValue:read(device))
  elseif state == SHADE_STATE_OPEN then
    device:emit_event(capabilities.windowShade.windowShade.opening())
  elseif state == SHADE_STATE_CLOSE then
    device:emit_event(capabilities.windowShade.windowShade.closing())
  end
end

local function device_info_changed(driver, device, event, args)
  if device.preferences ~= nil then
    local reverseRollerShadeDirPrefValue = device.preferences[reverseRollerShadeDir.ID]
    if reverseRollerShadeDirPrefValue ~= nil and
      reverseRollerShadeDirPrefValue ~= args.old_st_store.preferences[reverseRollerShadeDir.ID] then
      local raw_value = reverseRollerShadeDirPrefValue and true or false
      device:send(cluster_base.write_manufacturer_specific_attribute(device, aqara_utils.PRIVATE_CLUSTER_ID,
        DIRECTION_ATTRIBUTE_ID, aqara_utils.MFG_CODE, data_types.Boolean, raw_value))
    end
  end
end

local function device_added(driver, device)
  device:emit_event(capabilities.windowShade.supportedWindowShadeCommands({ "open", "close", "pause" },
    { visibility = { displayed = false } }))
  window_treatment_utils.emit_event_if_latest_state_missing(device, "main", capabilities.windowShadeLevel,
    capabilities.windowShadeLevel.shadeLevel.NAME, capabilities.windowShadeLevel.shadeLevel(0))
  window_treatment_utils.emit_event_if_latest_state_missing(device, "main", capabilities.windowShade,
    capabilities.windowShade.windowShade.NAME, capabilities.windowShade.windowShade.closed())
  window_treatment_utils.emit_event_if_latest_state_missing(device, "main", initializedStateWithGuide,
    initializedStateWithGuide.initializedStateWithGuide.NAME,
    initializedStateWithGuide.initializedStateWithGuide.notInitialized())
  device:emit_event(shadeRotateState.rotateState.idle({ visibility = { displayed = false } }))
  device:send(cluster_base.write_manufacturer_specific_attribute(device, aqara_utils.PRIVATE_CLUSTER_ID,
    aqara_utils.PRIVATE_ATTRIBUTE_ID, aqara_utils.MFG_CODE, data_types.Uint8, 1))
end

local function do_configure(self, device)
  device:configure()
  device:send(Groups.server.commands.RemoveAllGroups(device))
  do_refresh(self, device)
end

local aqara_roller_shade_t1s_handler = {
  NAME = "Aqara T1S Blinder Controller Handler",
  lifecycle_handlers = {
    added = device_added,
    doConfigure = do_configure,
    infoChanged = device_info_changed
  },
  capability_handlers = {
    [capabilities.windowShadeLevel.ID] = {
      [capabilities.windowShadeLevel.commands.setShadeLevel.NAME] = window_shade_level_cmd
    },
    [capabilities.windowShade.ID] = {
      [capabilities.windowShade.commands.open.NAME] = window_shade_open_cmd,
      [capabilities.windowShade.commands.close.NAME] = window_shade_close_cmd,
      -- [capabilities.windowShade.commands.pause.NAME] = window_shade_pause_cmd,
    },
    [shadeRotateState.ID] = {
      [setRotateStateCommandName] = set_rotate_command_handler
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    }
  },
  zigbee_handlers = {
    attr = {
      [aqara_utils.PRIVATE_CLUSTER_ID] = {
        [INIT_STATE_ATTRIBUTE_ID] = init_state_handler,
      },
      [AnalogOutput.ID] = {
        [AnalogOutput.attributes.PresentValue.ID] = shade_level_report_handler
      },
      [MULTISTATE_CLUSTER_ID] = {
        [MULTISTATE_ATTRIBUTE_ID] = shade_state_report_handler
      }
    }
  },
  can_handle = require("aqara.roller-shade.t1s.can_handle"),
}

return aqara_roller_shade_t1s_handler
