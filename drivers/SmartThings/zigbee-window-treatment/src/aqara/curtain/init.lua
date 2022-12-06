local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local aqara_utils = require "aqara/aqara_utils"
local zcl_commands = require "st.zigbee.zcl.global_commands"

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
  print("-------------- window_shade_level_cmd ")

  aqara_utils.shade_level_cmd(driver, device, command)
end

local function window_shade_open_cmd(driver, device, command)
  print("-------------- window_shade_open_cmd ")

  aqara_utils.shade_open_cmd(driver, device, command)
end

local function window_shade_close_cmd(driver, device, command)
  print("-------------- window_shade_close_cmd ")

  aqara_utils.shade_close_cmd(driver, device, command)
end

local function window_shade_pause_cmd(driver, device, command)
  print("-------------- window_shade_pause_cmd ")

  aqara_utils.shade_pause_cmd(driver, device, command)
end

local function write_initialize(device)
  aqara_utils.write_pref_attribute(device, PREF_INITIALIZE)
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
      aqara_utils.send_close_cmd(device, command)
    else
      device:emit_event(deviceInitialization.initializedState.initializing())
      setInitializationField(device, INIT_STATE_OPEN)
      aqara_utils.send_open_cmd(device, command)
    end
  end)
end

local function shade_level_read_handler(driver, device, zb_rx)
  print("-------------- shade_level_read_handler ")

  for i, v in ipairs(zb_rx.body.zcl_body.attr_records) do
    print(v.attr_id.value)
    if (v.attr_id.value == AnalogOutput.attributes.PresentValue.ID) then
      print("in")

      local level = v.data.value
      aqara_utils.emit_shade_state_event(device, level)
      break
    end
  end
end

local function shade_level_report_handler_legacy(driver, device, value, zb_rx)
  print("-------------- shade_level_report_handler_legacy ")

  -- Not implemented for legacy devices
end

local function shade_level_report_handler(driver, device, value, zb_rx)
  print("-------------- shade_level_report_handler ")
  print(value.value)

  aqara_utils.shade_position_changed(device, value)
end

local function shade_state_report_handler(driver, device, value, zb_rx)
  print("-------------- shade_state_report_handler ")
  print(value.value)

  aqara_utils.shade_state_changed(device, value)

  -- initializedState
  local state = value.value
  if state == aqara_utils.SHADE_STATE_STOP then
    local init_state_value = getInitializationField(device)
    if init_state_value == INIT_STATE_OPEN then
      device:set_field(INIT_STATE, INIT_STATE_REVERSE)
      aqara_utils.send_lift_percentage_cmd(device, { component = "main" }, 0)
    elseif init_state_value == INIT_STATE_CLOSE then
      device:set_field(INIT_STATE, INIT_STATE_REVERSE)
      aqara_utils.send_lift_percentage_cmd(device, { component = "main" }, 100)
    elseif init_state_value == INIT_STATE_REVERSE then
      device:set_field(INIT_STATE, "")
      aqara_utils.read_pref_attribute(device)
    end
  end
end

local function pref_report_handler(driver, device, value, zb_rx)
  -- initializedState
  local initialized = string.byte(value.value, 3) & 0xFF
  print(initialized)

  local reverse = string.byte(value.value, 4) & 0xFF
  print(reverse)
  local soft = string.byte(value.value, 6) & 0xFF
  print(soft)

  -- Do not update if in progress.
  local init_state_value = getInitializationField(device)
  if init_state_value == "" then
    device:emit_event(initialized == 1 and deviceInitialization.initializedState.initialized() or
      deviceInitialization.initializedState.notInitialized())
  end
end

local function write_soft_touch_preference(device, args)
  if device.preferences ~= nil then
    if device.preferences[softTouchPreferenceId] ~= args.old_st_store.preferences[softTouchPreferenceId] then
      if device.preferences[softTouchPreferenceId] == true then
        aqara_utils.write_pref_attribute(device, PREF_SOFT_TOUCH_ON)
      else
        aqara_utils.write_pref_attribute(device, PREF_SOFT_TOUCH_OFF)
      end
    end
  end
end

local function write_reverse_preferences(device, args)
  if device.preferences ~= nil then
    if device.preferences[reverseCurtainDirectionPreferenceId] ~=
        args.old_st_store.preferences[reverseCurtainDirectionPreferenceId] then
      if device.preferences[reverseCurtainDirectionPreferenceId] == true then
        aqara_utils.write_reverse_pref_on(device)
      else
        aqara_utils.write_reverse_pref_off(device)
      end

      -- read updated value
      device.thread:call_with_delay(2, function(d)
        aqara_utils.read_pref_attribute(device)
      end)
    end
  end
end

local function do_refresh(self, device)
  aqara_utils.read_shade_position_attribute(device)
  aqara_utils.read_pref_attribute(device)
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

  aqara_utils.enable_private_cluster_attribute(device)
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
  can_handle = function(opts, driver, device)
    return aqara_utils.is_matched_profile(device, "curtain")
  end
}

return aqara_curtain_handler
