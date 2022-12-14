local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local aqara_utils = require "aqara/aqara_utils"
local zcl_commands = require "st.zigbee.zcl.global_commands"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"

local Basic = clusters.Basic
local WindowCovering = clusters.WindowCovering
local AnalogOutput = clusters.AnalogOutput

local deviceInitialization = capabilities["stse.deviceInitialization"]
local deviceInitializationId = "stse.deviceInitialization"
local setInitializedStateCommandName = "setInitializedState"

local reverseCurtainDirectionPreferenceId = "stse.reverseCurtainDirection"
local softTouchPreferenceId = "stse.softTouch"

local INIT_STATE = "initState"
local INIT_STATE_INIT = "init"
local INIT_STATE_OPEN = "open"
local INIT_STATE_CLOSE = "close"
local INIT_STATE_REVERSE = "reverse"

local PREF_INITIALIZE = "\x00\x01\x00\x00\x00\x00\x00"
local PREF_SOFT_TOUCH_OFF = "\x00\x08\x00\x00\x00\x01\x00"
local PREF_SOFT_TOUCH_ON = "\x00\x08\x00\x00\x00\x00\x00"

local function window_shade_level_cmd(driver, device, command)
  aqara_utils.shade_level_cmd(driver, device, command)
end

local function window_shade_open_cmd(driver, device, command)
  device:send_to_component(command.component, WindowCovering.server.commands.GoToLiftPercentage(device, 100))
end

local function window_shade_close_cmd(driver, device, command)
  device:send_to_component(command.component, WindowCovering.server.commands.GoToLiftPercentage(device, 0))
end

local function window_shade_pause_cmd(driver, device, command)
  device:send_to_component(command.component, WindowCovering.server.commands.Stop(device))
end

local function write_initialize(device)
  device:send(cluster_base.write_manufacturer_specific_attribute(device, Basic.ID, aqara_utils.PREF_ATTRIBUTE_ID,
    aqara_utils.MFG_CODE, data_types.CharString, PREF_INITIALIZE))
end

local function setInitializationField(device, value)
  device:set_field(INIT_STATE, value)
end

local function getInitializationField(device)
  return device:get_field(INIT_STATE) or ""
end

local function set_initialized_state_handler(driver, device, command)
  -- update ui
  device:emit_event(deviceInitialization.initializedState.initializing())

  -- initialize
  setInitializationField(device, INIT_STATE_INIT)
  write_initialize(device)

  -- open/close command
  device.thread:call_with_delay(3, function(d)
    local lastLevel = device:get_latest_state("main", capabilities.windowShadeLevel.ID,
      capabilities.windowShadeLevel.shadeLevel.NAME) or 0
    if lastLevel > 0 then
      setInitializationField(device, INIT_STATE_CLOSE)
      device:send_to_component(command.component, WindowCovering.server.commands.GoToLiftPercentage(device, 0))
    else
      device:emit_event(deviceInitialization.initializedState.initializing())
      setInitializationField(device, INIT_STATE_OPEN)
      device:send_to_component(command.component, WindowCovering.server.commands.GoToLiftPercentage(device, 100))
    end
  end)
end

local function shade_level_read_handler(driver, device, zb_rx)
  for i, v in ipairs(zb_rx.body.zcl_body.attr_records) do
    if (v.attr_id.value == AnalogOutput.attributes.PresentValue.ID) then
      local level = v.data.value
      aqara_utils.emit_shade_state_event(device, level)
      break
    end
  end
end

local function shade_level_report_handler_legacy(driver, device, value, zb_rx)
  -- Not implemented for legacy devices
end

local function shade_level_report_handler(driver, device, value, zb_rx)
  aqara_utils.shade_position_changed(device, value)
end

local function shade_state_report_handler(driver, device, value, zb_rx)
  aqara_utils.shade_state_changed(device, value)

  -- initializedState
  local state = value.value
  if state == aqara_utils.SHADE_STATE_STOP then
    local init_state_value = getInitializationField(device)
    if init_state_value == INIT_STATE_OPEN then
      device:set_field(INIT_STATE, INIT_STATE_REVERSE)
      device:send_to_component("main", WindowCovering.server.commands.GoToLiftPercentage(device, 0))
    elseif init_state_value == INIT_STATE_CLOSE then
      device:set_field(INIT_STATE, INIT_STATE_REVERSE)
      device:send_to_component("main", WindowCovering.server.commands.GoToLiftPercentage(device, 100))
    elseif init_state_value == INIT_STATE_REVERSE then
      device:set_field(INIT_STATE, "")
      device:send(cluster_base.read_manufacturer_specific_attribute(device, Basic.ID, aqara_utils.PREF_ATTRIBUTE_ID,
        aqara_utils.MFG_CODE))
    end
  end
end

local function pref_report_handler(driver, device, value, zb_rx)
  -- initializedState
  local initialized = string.byte(value.value, 3) & 0xFF

  -- Do not update if in progress.
  local init_state_value = getInitializationField(device)
  if init_state_value == "" then
    device:emit_event(initialized == 1 and deviceInitialization.initializedState.initialized() or
      deviceInitialization.initializedState.notInitialized())
  end
end

local function write_soft_touch_preference(device, args)
  if device.preferences ~= nil then
    local softTouchPrefValue = device.preferences[softTouchPreferenceId]
    if softTouchPrefValue ~= nil and
        softTouchPrefValue ~= args.old_st_store.preferences[softTouchPreferenceId] then
      local raw_value = softTouchPrefValue and PREF_SOFT_TOUCH_ON or PREF_SOFT_TOUCH_OFF
      device:send(cluster_base.write_manufacturer_specific_attribute(device, Basic.ID, aqara_utils.PREF_ATTRIBUTE_ID,
        aqara_utils.MFG_CODE, data_types.CharString, raw_value))
    end
  end
end

local function write_reverse_preferences(device, args)
  if device.preferences ~= nil then
    local reverseCurtainDirectionPrefValue = device.preferences[reverseCurtainDirectionPreferenceId]
    if reverseCurtainDirectionPrefValue ~= nil and reverseCurtainDirectionPrefValue ~=
        args.old_st_store.preferences[reverseCurtainDirectionPreferenceId] then
      local raw_value = reverseCurtainDirectionPrefValue and aqara_utils.PREF_REVERSE_ON or aqara_utils.PREF_REVERSE_OFF
      device:send(cluster_base.write_manufacturer_specific_attribute(device, Basic.ID, aqara_utils.PREF_ATTRIBUTE_ID,
        aqara_utils.MFG_CODE, data_types.CharString, raw_value))

      -- read updated value
      device.thread:call_with_delay(2, function(d)
        device:send(cluster_base.read_manufacturer_specific_attribute(device, Basic.ID, aqara_utils.PREF_ATTRIBUTE_ID,
          aqara_utils.MFG_CODE))
      end)
    end
  end
end

local function do_refresh(self, device)
  device:send(AnalogOutput.attributes.PresentValue:read(device))
  device:send(cluster_base.read_manufacturer_specific_attribute(device, Basic.ID, aqara_utils.PREF_ATTRIBUTE_ID,
    aqara_utils.MFG_CODE))
end

local function device_info_changed(driver, device, event, args)
  write_reverse_preferences(device, args) -- reverse direction
  write_soft_touch_preference(device, args) -- soft touch
end

local function do_configure(self, device)
  device:configure()
  do_refresh(self, device)
end

local function device_added(driver, device)
  device:emit_event(capabilities.windowShade.supportedWindowShadeCommands({ "open", "close", "pause" }))
  device:emit_event(deviceInitialization.supportedInitializedState({ "notInitialized", "initializing", "initialized" }))
  device:emit_event(capabilities.windowShadeLevel.shadeLevel(0))
  device:emit_event(capabilities.windowShade.windowShade.closed())
  device:emit_event(deviceInitialization.initializedState.notInitialized())

  device:send(cluster_base.write_manufacturer_specific_attribute(device, aqara_utils.PRIVATE_CLUSTER_ID,
    aqara_utils.PRIVATE_ATTRIBUTE_ID, aqara_utils.MFG_CODE, data_types.Uint8, 1))

  -- Initial default settings
  device:send(cluster_base.write_manufacturer_specific_attribute(device, Basic.ID, aqara_utils.PREF_ATTRIBUTE_ID,
    aqara_utils.MFG_CODE, data_types.CharString, aqara_utils.PREF_REVERSE_OFF))
  device:send(cluster_base.write_manufacturer_specific_attribute(device, Basic.ID, aqara_utils.PREF_ATTRIBUTE_ID,
    aqara_utils.MFG_CODE, data_types.CharString, PREF_SOFT_TOUCH_ON))
end

local aqara_curtain_handler = {
  NAME = "Aqara Curtain Handler",
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
    [deviceInitializationId] = {
      [setInitializedStateCommandName] = set_initialized_state_handler
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    }
  },
  zigbee_handlers = {
    global = {
      [AnalogOutput.ID] = {
        [zcl_commands.ReadAttributeResponse.ID] = shade_level_read_handler
      }
    },
    attr = {
      [WindowCovering.ID] = {
        [WindowCovering.attributes.CurrentPositionLiftPercentage.ID] = shade_level_report_handler_legacy
      },
      [AnalogOutput.ID] = {
        [AnalogOutput.attributes.PresentValue.ID] = shade_level_report_handler
      },
      [Basic.ID] = {
        [aqara_utils.PREF_ATTRIBUTE_ID] = pref_report_handler,
        [aqara_utils.SHADE_STATE_ATTRIBUTE_ID] = shade_state_report_handler
      }
    }
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_model() == "lumi.curtain" or device:get_model() == "lumi.curtain.v1"
  end
}

return aqara_curtain_handler
