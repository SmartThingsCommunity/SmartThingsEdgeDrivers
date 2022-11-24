local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local aqara_utils = require "aqara/aqara_utils"
local data_types = require "st.zigbee.data_types"
local FrameCtrl = require "st.zigbee.zcl.frame_ctrl"

local Basic = clusters.Basic

local initializedStateWithGuide = capabilities["stse.initializedStateWithGuide"]
local reverseRollerShadeDirId = "stse.reverseRollerShadeDir"

local shadeRotateState = capabilities["stse.shadeRotateState"]
local shadeRotateStateId = "stse.shadeRotateState"
local setRotateStateCommandName = "setRotateState"

local MULTISTATE_CLUSTER_ID = 0x0013
local MULTISTATE_ATTRIBUTE_ID = 0x0055
local TILT_UP_VALUE = 0x0004
local TILT_DOWN_VALUE = 0x0005

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
  if aqara_utils.isInitializedStateField(device) ~= true then
    return
  end

  local state = command.args.state
  if state == "rotateUp" then
    write_tilt_attribute(device, TILT_UP_VALUE)
  elseif state == "rotateDown" then
    write_tilt_attribute(device, TILT_DOWN_VALUE)
  end

  device:emit_event(shadeRotateState.rotateState.idle())
end

local function shade_state_attr_handler(driver, device, value, zb_rx)
  aqara_utils.shade_state_changed(device, value)
end

local function pref_attr_handler(driver, device, value, zb_rx)
  local initialized = string.byte(value.value, 3) & 0xFF
  device:emit_event(initialized == 1 and initializedStateWithGuide.initializedStateWithGuide.initialized() or
    initializedStateWithGuide.initializedStateWithGuide.notInitialized())

  -- store
  aqara_utils.setInitializedStateField(device, initialized)
end

local function write_reverse_preferences(device, args)
  if device.preferences ~= nil then
    if device.preferences[reverseRollerShadeDirId] ~=
        args.old_st_store.preferences[reverseRollerShadeDirId] then
      if device.preferences[reverseRollerShadeDirId] == true then
        aqara_utils.write_reverse_pref_on(device)
      else
        aqara_utils.write_reverse_pref_off(device)
      end
    end
  end
end

local function do_refresh(self, device)
  aqara_utils.read_present_value_attribute(device)
  aqara_utils.read_pref_attribute(device)
end

local function device_info_changed(driver, device, event, args)
  write_reverse_preferences(device, args)
end

local function do_configure(self, device)
  device:configure()

  do_refresh(self, device)
end

local function device_added(driver, device)
  device:emit_event(capabilities.windowShade.supportedWindowShadeCommands({ "open", "close", "pause" }))
  device:emit_event(shadeRotateState.rotateState.idle())

  aqara_utils.write_reverse_pref_default(device)
end

local aqara_roller_shade_handler = {
  NAME = "Aqara Roller Shade Handler",
  lifecycle_handlers = {
    added = device_added,
    doConfigure = do_configure,
    infoChanged = device_info_changed
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    },
    [shadeRotateStateId] = {
      [setRotateStateCommandName] = set_rotate_command_handler
    }
  },
  zigbee_handlers = {
    attr = {
      [Basic.ID] = {
        [aqara_utils.SHADE_STATE_ATTRIBUTE_ID] = shade_state_attr_handler,
        [aqara_utils.PREF_ATTRIBUTE_ID] = pref_attr_handler
      }
    }
  },
  can_handle = function(opts, driver, device)
    return aqara_utils.is_matched_profile(device, "roller-shade")
  end
}

return aqara_roller_shade_handler
