local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local FrameCtrl = require "st.zigbee.zcl.frame_ctrl"
local data_types = require "st.zigbee.data_types"
local aqara_utils = require "aqara/aqara_utils"

local Basic = clusters.Basic
local WindowCovering = clusters.WindowCovering

local initializedStateWithGuide = capabilities["stse.initializedStateWithGuide"]
local reverseRollerShadeDirId = "stse.reverseRollerShadeDir"

local shadeRotateState = capabilities["stse.shadeRotateState"]
local shadeRotateStateId = "stse.shadeRotateState"
local setRotateStateCommandName = "setRotateState"

local MULTISTATE_CLUSTER_ID = 0x0013
local MULTISTATE_ATTRIBUTE_ID = 0x0055
local TILT_UP_VALUE = 0x0004
local TILT_DOWN_VALUE = 0x0005

local INITIALIZED_STATE = "initializedState"

local function window_shade_level_cmd(driver, device, command)
  -- Cannot be controlled if not initialized
  local initialized = device:get_field(INITIALIZED_STATE) or 0
  if initialized ~= 1 then
    return
  end

  aqara_utils.shade_level_cmd(driver, device, command)
end

local function window_shade_open_cmd(driver, device, command)
  -- Cannot be controlled if not initialized
  local initialized = device:get_field(INITIALIZED_STATE) or 0
  if initialized ~= 1 then
    return
  end

  device:send_to_component(command.component, WindowCovering.server.commands.GoToLiftPercentage(device, 100))
end

local function window_shade_close_cmd(driver, device, command)
  -- Cannot be controlled if not initialized
  local initialized = device:get_field(INITIALIZED_STATE) or 0
  if initialized ~= 1 then
    return
  end

  device:send_to_component(command.component, WindowCovering.server.commands.GoToLiftPercentage(device, 0))
end

local function write_tilt_attribute(device, payload)
  local value = data_types.validate_or_build_type(payload, data_types.Uint16, "payload")
  local message = cluster_base.write_attribute(device, data_types.ClusterId(MULTISTATE_CLUSTER_ID),
    data_types.AttributeId(MULTISTATE_ATTRIBUTE_ID), value)
  local frm_ctrl = FrameCtrl(0x10)
  message.body.zcl_header.frame_ctrl:set_mfg_specific()
  message.body.zcl_header.mfg_code = data_types.validate_or_build_type(aqara_utils.MFG_CODE, data_types.Uint16,
    "mfg_code")
  message.body.zcl_header.frame_ctrl = frm_ctrl
  device:send(message)
end

local function set_rotate_command_handler(driver, device, command)
  device:emit_event(shadeRotateState.rotateState.idle()) -- update UI

  local initialized = device:get_field(INITIALIZED_STATE) or 0
  if initialized ~= 1 then
    return
  end

  local state = command.args.state
  if state == "rotateUp" then
    write_tilt_attribute(device, TILT_UP_VALUE)
  elseif state == "rotateDown" then
    write_tilt_attribute(device, TILT_DOWN_VALUE)
  end
end

local function shade_state_report_handler(driver, device, value, zb_rx)
  aqara_utils.shade_state_changed(device, value)
end

local function pref_report_handler(driver, device, value, zb_rx)
  -- initializedState
  local initialized = string.byte(value.value, 3) & 0xFF
  device:emit_event(initialized == 1 and initializedStateWithGuide.initializedStateWithGuide.initialized() or
    initializedStateWithGuide.initializedStateWithGuide.notInitialized())

  -- store
  device:set_field(INITIALIZED_STATE, initialized, { persist = true })
end

local function write_reverse_preferences(device, args)
  if device.preferences ~= nil then
    local reverseRollerShadeDirPrefValue = device.preferences[reverseRollerShadeDirId]
    if reverseRollerShadeDirPrefValue ~= nil and
        reverseRollerShadeDirPrefValue ~= args.old_st_store.preferences[reverseRollerShadeDirId] then
      local raw_value = reverseRollerShadeDirPrefValue and aqara_utils.PREF_REVERSE_ON or aqara_utils.PREF_REVERSE_OFF
      device:send(cluster_base.write_manufacturer_specific_attribute(device, Basic.ID, aqara_utils.PREF_ATTRIBUTE_ID,
        aqara_utils.MFG_CODE, data_types.CharString, raw_value))
    end
  end
end

local function device_info_changed(driver, device, event, args)
  write_reverse_preferences(device, args)
end

local function device_added(driver, device)
  device:emit_event(capabilities.windowShade.supportedWindowShadeCommands({ "open", "close", "pause" }))
  device:emit_event(capabilities.windowShadeLevel.shadeLevel(0))
  device:emit_event(capabilities.windowShade.windowShade.closed())
  device:emit_event(initializedStateWithGuide.initializedStateWithGuide.notInitialized())
  device:emit_event(shadeRotateState.rotateState.idle())

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
    [capabilities.windowShade.ID] = {
      [capabilities.windowShade.commands.open.NAME] = window_shade_open_cmd,
      [capabilities.windowShade.commands.close.NAME] = window_shade_close_cmd,
    },
    [shadeRotateStateId] = {
      [setRotateStateCommandName] = set_rotate_command_handler
    }
  },
  zigbee_handlers = {
    attr = {
      [Basic.ID] = {
        [aqara_utils.SHADE_STATE_ATTRIBUTE_ID] = shade_state_report_handler,
        [aqara_utils.PREF_ATTRIBUTE_ID] = pref_report_handler
      }
    }
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_model() == "lumi.curtain.aq2"
  end
}

return aqara_roller_shade_handler
