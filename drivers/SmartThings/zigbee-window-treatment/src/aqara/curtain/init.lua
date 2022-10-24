local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local aqara_utils = require "aqara/aqara_utils"
local log = require "log"

local Basic = clusters.Basic
local AnalogOutput = clusters.AnalogOutput
local Groups = clusters.Groups

local softTouchPreferenceId = "stse.softTouch"

local INIT_STATE = "initState"
local INIT_STATE_OPEN = "open"
local INIT_STATE_CLOSE = "close"
local INIT_STATE_REVERSE = "reverse"
local INIT_STATE_DONE = "done"

local PREF_SOFT_TOUCH_OFF = "\x00\x08\x00\x00\x00\x01\x00"
local PREF_SOFT_TOUCH_ON = "\x00\x08\x00\x00\x00\x00\x00"

local function setInitializationField(device, value)
  device:set_field(INIT_STATE, value)
end

local function getInitializationField(device)
  return device:get_field(INIT_STATE) or INIT_STATE_DONE
end

local function set_initialized_state_handler(driver, device, command)
  log.debug("-----------> set_initialized_state_handler " .. command.component)

  -- initialize
  aqara_utils.write_initialize(device)

  -- update ui
  device:emit_event(aqara_utils.deviceInitialization.initializedState.initializing())

  -- open/close command
  device.thread:call_with_delay(2, function(d)
    local lastLevel = device:get_latest_state("main", capabilities.windowShadeLevel.ID,
      capabilities.windowShadeLevel.shadeLevel.NAME) or 0
    if lastLevel > 0 then
      setInitializationField(device, INIT_STATE_CLOSE)
      aqara_utils.send_close_cmd(device, command.component)
    else
      setInitializationField(device, INIT_STATE_OPEN)
      aqara_utils.send_open_cmd(device, command.component)
    end
  end)
end

local function shade_state_attr_handler(driver, device, value, zb_rx)
  aqara_utils.shade_state_changed(device, value)

  -- update initialization ui
  local state = value.value
  if state == aqara_utils.SHADE_STATE_STOP then
    local flag = getInitializationField(device)
    if flag == INIT_STATE_CLOSE then
      setInitializationField(device, INIT_STATE_REVERSE)
      aqara_utils.send_open_cmd(device, "main")
    elseif flag == INIT_STATE_OPEN then
      setInitializationField(device, INIT_STATE_REVERSE)
      aqara_utils.send_close_cmd(device, "main")
    elseif flag == INIT_STATE_REVERSE then
      setInitializationField(device, INIT_STATE_DONE)
      aqara_utils.read_pref_attribute(device)
    end
  end
end

local function current_position_attr_handler(driver, device, value, zb_rx)
  aqara_utils.shade_position_changed(device, value)
end

local function pref_attr_handler(driver, device, value, zb_rx)
  local initialized = string.byte(value.value, 3) & 0xFF
  local flag = getInitializationField(device)
  if flag == INIT_STATE_DONE then
    device:emit_event(initialized == 1 and aqara_utils.deviceInitialization.initializedState.initialized() or
      aqara_utils.deviceInitialization.initializedState.notInitialized())
  end
end

local function write_soft_touch_preference(device, args)
  if device.preferences[softTouchPreferenceId] ~= args.old_st_store.preferences[softTouchPreferenceId] then
    if device.preferences[softTouchPreferenceId] == true then
      aqara_utils.write_pref_attribute(device, PREF_SOFT_TOUCH_ON)
    else
      aqara_utils.write_pref_attribute(device, PREF_SOFT_TOUCH_OFF)
    end
  end
end

local function do_refresh(self, device)
  device:send(AnalogOutput.attributes.PresentValue:read(device))

  aqara_utils.read_pref_attribute(device)
end

local function device_info_changed(driver, device, event, args)
  if device.preferences ~= nil then
    -- reverse direction
    aqara_utils.write_reverse_preferences(device, args)
    -- soft touch
    write_soft_touch_preference(device, args)
  end
end

local function do_configure(self, device)
  device:configure()

  device:send(Groups.server.commands.RemoveAllGroups(device))

  do_refresh(self, device)
end

local function device_added(driver, device)
  local main_comp = device.profile.components["main"]
  device:emit_component_event(main_comp,
    capabilities.windowShade.supportedWindowShadeCommands({ "open", "close", "pause" }))
  device:emit_component_event(main_comp, aqara_utils.deviceInitialization.supportedInitializedState(
    { "notInitialized", "initializing", "initialized" }))

  device:send(Groups.server.commands.RemoveAllGroups(device))

  -- Set default value to the device.
  aqara_utils.write_pref_attribute(device, aqara_utils.PREF_REVERSE_DEFAULT)
  aqara_utils.write_pref_attribute(device, PREF_SOFT_TOUCH_ON)
end

local aqara_curtain_handler = {
  NAME = "Aqara Curtain Handler",
  lifecycle_handlers = {
    added = device_added,
    doConfigure = do_configure,
    infoChanged = device_info_changed
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    },
    [aqara_utils.deviceInitializationId] = {
      [aqara_utils.setInitializedStateCommandName] = set_initialized_state_handler
    }
  },
  zigbee_handlers = {
    attr = {
      [Basic.ID] = {
        [aqara_utils.SHADE_STATE_ATTR_ID] = shade_state_attr_handler,
        [aqara_utils.PREF_ATTRIBUTE_ID] = pref_attr_handler
      },
      [AnalogOutput.ID] = {
        [AnalogOutput.attributes.PresentValue.ID] = current_position_attr_handler
      }
    }
  },
  can_handle = function(opts, driver, device)
    return aqara_utils.is_matched_profile(device, "curtain")
  end
}

return aqara_curtain_handler
