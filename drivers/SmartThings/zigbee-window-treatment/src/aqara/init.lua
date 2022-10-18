local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local utils = require "st.utils"

local deviceInitialization = capabilities["stse.deviceInitialization"]
local deviceInitializationId = "stse.deviceInitialization"
local setInitializedStateCommandName = "setInitializedState"
local reverseCurtainDirectionPreferenceId = "stse.reverseCurtainDirection"
local softTouchPreferenceId = "stse.softTouch"

local Basic = clusters.Basic
local WindowCovering = clusters.WindowCovering
local AnalogOutput = clusters.AnalogOutput
local Groups = clusters.Groups
local MFG_CODE = 0x115F
local PREF_ATTRIBUTE_ID = 0x0401
local SHADE_STATE_ATTR_ID = 0x0404
local INIT_STATE = "initState"
local INIT_STATE_OPEN = "open"
local INIT_STATE_CLOSE = "close"
local INIT_STATE_REVERSE = "reverse"
local INIT_STATE_DONE = "done"
local SHADE_LEVEL = "shadeLevel"
local SHADE_STATE = "shadeState"
local SHADE_STATE_STOP = 0
local SHADE_STATE_OPEN = 1
local SHADE_STATE_CLOSE = 2
local PREF_REVERSE_OFF = "\x00\x02\x00\x00\x00\x00\x00"
local PREF_REVERSE_ON = "\x00\x02\x00\x01\x00\x00\x00"
local PREF_SOFT_TOUCH_OFF = "\x00\x08\x00\x00\x00\x01\x00"
local PREF_SOFT_TOUCH_ON = "\x00\x08\x00\x00\x00\x00\x00"
local PREF_INITIALIZE = "\x00\x01\x00\x00\x00\x00\x00"

local FINGERPRINTS = {
  { mfr = "LUMI", model = "lumi.curtain" },
  { mfr = "LUMI", model = "lumi.curtain.v1" }
}

local is_aqara_products = function(opts, driver, device)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local read_custom_attribute = function(device, cluster_id, attribute)
  local message = cluster_base.read_attribute(device, data_types.ClusterId(cluster_id), attribute)
  message.body.zcl_header.frame_ctrl:set_mfg_specific()
  message.body.zcl_header.mfg_code = data_types.validate_or_build_type(MFG_CODE, data_types.Uint16, "mfg_code")
  return message
end

local read_pref_attribute = function(device)
  device:send(read_custom_attribute(device, Basic.ID, PREF_ATTRIBUTE_ID))
end

local write_pref_attribute = function(device, str)
  device:send(cluster_base.write_manufacturer_specific_attribute(device, Basic.ID, PREF_ATTRIBUTE_ID, MFG_CODE,
    data_types.CharString, str))
end

local function send_open_cmd(device, component)
  device:send_to_component(component, WindowCovering.server.commands.GoToLiftPercentage(device, 100))
end

local function send_close_cmd(device, component)
  device:send_to_component(component, WindowCovering.server.commands.GoToLiftPercentage(device, 0))
end

local do_refresh = function(self, device)
  device:send(AnalogOutput.attributes.PresentValue:read(device))

  read_pref_attribute(device)
end

local do_configure = function(self, device)
  device:configure()

  device:send(Groups.server.commands.RemoveAllGroups(device))

  do_refresh(self, device)
end

local function device_added(driver, device)
  local main_comp = device.profile.components["main"]
  device:emit_component_event(main_comp,
    capabilities.windowShade.supportedWindowShadeCommands({ "open", "close", "pause" }, { visibility = { displayed = false } }))
  device:emit_component_event(main_comp,
    deviceInitialization.supportedInitializedState({ "notInitialized", "initializing", "initialized" }))

  device:send(Groups.server.commands.RemoveAllGroups(device))

  -- Set default value to the device.
  write_pref_attribute(device, PREF_REVERSE_OFF)
  write_pref_attribute(device, PREF_SOFT_TOUCH_ON)
end

local function device_info_changed(driver, device, event, args)
  if device.preferences ~= nil then
    if device.preferences[reverseCurtainDirectionPreferenceId] ~=
        args.old_st_store.preferences[reverseCurtainDirectionPreferenceId] then
      if device.preferences[reverseCurtainDirectionPreferenceId] == true then
        write_pref_attribute(device, PREF_REVERSE_ON)
      else
        write_pref_attribute(device, PREF_REVERSE_OFF)
      end

      device.thread:call_with_delay(2, function(d)
        read_pref_attribute(device)
      end)
    end

    if device.preferences[softTouchPreferenceId] ~= args.old_st_store.preferences[softTouchPreferenceId] then
      if device.preferences[softTouchPreferenceId] == true then
        write_pref_attribute(device, PREF_SOFT_TOUCH_ON)
      else
        write_pref_attribute(device, PREF_SOFT_TOUCH_OFF)
      end
    end
  end
end

local function setInitializationField(device, value)
  device:set_field(INIT_STATE, value)
end

local function getInitializationField(device)
  return device:get_field(INIT_STATE) or INIT_STATE_DONE
end

local function setShadeStateField(device, value)
  device:set_field(SHADE_STATE, value)
end

local function getShadeStateField(device)
  return device:get_field(SHADE_STATE) or SHADE_STATE_STOP
end

local function setShadeLevelField(device, value)
  device:set_field(SHADE_LEVEL, value)
end

local function getShadeLevelField(device)
  return device:get_field(SHADE_LEVEL) or 0
end

local function setInitializedState_handler(driver, device, command)
  write_pref_attribute(device, PREF_INITIALIZE)
  device:emit_event(deviceInitialization.initializedState.initializing())

  device.thread:call_with_delay(2, function(d)
    local lastLevel = device:get_latest_state("main", capabilities.windowShadeLevel.ID,
      capabilities.windowShadeLevel.shadeLevel.NAME) or 0
    if lastLevel > 0 then
      setInitializationField(device, INIT_STATE_CLOSE)
      send_close_cmd(device, command.component)
    else
      setInitializationField(device, INIT_STATE_OPEN)
      send_open_cmd(device, command.component)
    end
  end)
end

local function emit_shade_state_event(device, shadeLevel)
  if shadeLevel == 100 then
    device:emit_event(capabilities.windowShade.windowShade.open())
  elseif shadeLevel == 0 then
    device:emit_event(capabilities.windowShade.windowShade.closed())
  else
    device:emit_event(capabilities.windowShade.windowShade.partially_open())
  end
end

local function emit_shade_level_event(device, level)
  device:emit_event(capabilities.windowShadeLevel.shadeLevel(level))
end

local function window_shade_level_cmd(driver, device, command)
  local level = command.args.shadeLevel
  if level > 100 then
    level = 100
  end
  level = utils.round(level)
  device:send_to_component(command.component, WindowCovering.server.commands.GoToLiftPercentage(device, level))
  emit_shade_level_event(device, level)
end

local function window_shade_open_cmd(driver, device, command)
  send_open_cmd(device, command.component)

  local shadeLevel = getShadeLevelField(device)
  emit_shade_state_event(device, shadeLevel)
end

local function window_shade_close_cmd(driver, device, command)
  send_close_cmd(device, command.component)

  local shadeLevel = getShadeLevelField(device)
  emit_shade_state_event(device, shadeLevel)
end

local function window_shade_pause_cmd(driver, device, command)
  device:send_to_component(command.component, WindowCovering.server.commands.Stop(device))

  local shadeLevel = getShadeLevelField(device)
  emit_shade_state_event(device, shadeLevel)
end

local function shade_state_attr_handler(driver, device, value, zb_rx)
  local state = value.value
  setShadeStateField(device, state)

  if state == SHADE_STATE_STOP then
    local shadeLevel = getShadeLevelField(device)
    emit_shade_state_event(device, shadeLevel)

    local flag = getInitializationField(device)
    if flag == INIT_STATE_CLOSE then
      setInitializationField(device, INIT_STATE_REVERSE)
      send_open_cmd(device, "main")
    elseif flag == INIT_STATE_OPEN then
      setInitializationField(device, INIT_STATE_REVERSE)
      send_close_cmd(device, "main")
    elseif flag == INIT_STATE_REVERSE then
      setInitializationField(device, INIT_STATE_DONE)
      read_pref_attribute(device)
    end
  elseif state == SHADE_STATE_OPEN then
    device:emit_event(capabilities.windowShade.windowShade.opening())
  elseif state == SHADE_STATE_CLOSE then
    device:emit_event(capabilities.windowShade.windowShade.closing())
  end
end

local function current_position_attr_handler(driver, device, value, zb_rx)
  local level = value.value
  if level > 100 then
    level = 100
  end
  level = utils.round(level)

  setShadeLevelField(device, level)
  emit_shade_level_event(device, level)

  local shadeState = getShadeStateField(device)
  if shadeState == SHADE_STATE_STOP then
    emit_shade_state_event(device, level)
  end
end

local function pref_attr_handler(driver, device, value, zb_rx)
  local initialized = string.byte(value.value, 3) & 0xFF
  local flag = getInitializationField(device)
  if flag == INIT_STATE_DONE then
    device:emit_event(initialized == 1 and deviceInitialization.initializedState.initialized() or
      deviceInitialization.initializedState.notInitialized())
  end
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
    [capabilities.windowShade.ID] = {
      [capabilities.windowShade.commands.open.NAME] = window_shade_open_cmd,
      [capabilities.windowShade.commands.close.NAME] = window_shade_close_cmd,
      [capabilities.windowShade.commands.pause.NAME] = window_shade_pause_cmd
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    },
    [deviceInitializationId] = {
      [setInitializedStateCommandName] = setInitializedState_handler
    }
  },
  zigbee_handlers = {
    attr = {
      [Basic.ID] = {
        [SHADE_STATE_ATTR_ID] = shade_state_attr_handler,
        [PREF_ATTRIBUTE_ID] = pref_attr_handler,
      },
      [AnalogOutput.ID] = {
        [AnalogOutput.attributes.PresentValue.ID] = current_position_attr_handler,
      }
    }
  },
  can_handle = is_aqara_products,
}

return aqara_window_treatment_handler
