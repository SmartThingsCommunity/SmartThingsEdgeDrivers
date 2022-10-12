local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local utils = require "st.utils"
local aqara_utils = require "aqara/aqara_utils"
local log = require "log"


local Basic = clusters.Basic
local AnalogOutput = clusters.AnalogOutput
local Groups = clusters.Groups

local deviceInitialization = capabilities["stse.deviceInitialization"]
local deviceInitializationId = "stse.deviceInitialization"
local setInitializedStateCommandName = "setInitializedState"



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

local SHADE_STATE_ATTR_ID = 0x0404


local PREF_INITIALIZE = "\x00\x01\x00\x00\x00\x00\x00"


local FINGERPRINTS = {
  { mfr = "LUMI", model = "lumi.curtain.aq2" }

}

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

local function set_initialized_state_handler(driver, device, command)

  aqara_utils.write_pref_attribute(device, PREF_INITIALIZE)

  device:emit_event(deviceInitialization.initializedState.initializing())

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
  local state = value.value
  setShadeStateField(device, state)

  if state == SHADE_STATE_STOP then
    local shadeLevel = getShadeLevelField(device)
    aqara_utils.emit_shade_state_event(device, shadeLevel)


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
  aqara_utils.emit_shade_level_event(device, level)


  local shadeState = getShadeStateField(device)
  if shadeState == SHADE_STATE_STOP then
    aqara_utils.emit_shade_state_event(device, level)

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

local function do_refresh(self, device)
  device:send(AnalogOutput.attributes.PresentValue:read(device))

  aqara_utils.read_pref_attribute(device)

end

local function device_info_changed(driver, device, event, args)
  if device.preferences ~= nil then
    aqara_utils.check_reverse_preferences(driver, device, event, args)



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
  device:emit_component_event(main_comp, deviceInitialization.supportedInitializedState(
    { "notInitialized", "initializing", "initialized" }))

  device:send(Groups.server.commands.RemoveAllGroups(device))

  -- Set default value to the device.
  aqara_utils.write_pref_attribute(device, aqara_utils.PREF_REVERSE_DEFAULT)

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
    [deviceInitializationId] = {
      [setInitializedStateCommandName] = set_initialized_state_handler
    }
  },
  zigbee_handlers = {
    attr = {
      [Basic.ID] = {
        [SHADE_STATE_ATTR_ID] = shade_state_attr_handler,
        [aqara_utils.PREF_ATTRIBUTE_ID] = pref_attr_handler

      },
      [AnalogOutput.ID] = {
        [AnalogOutput.attributes.PresentValue.ID] = current_position_attr_handler
      }
    }
  },
  can_handle = function(opts, driver, device)
    for _, fingerprint in ipairs(FINGERPRINTS) do
      if device:get_model() == fingerprint.model then
        return true
      end
    end
    return false
  end
}

return aqara_roller_shade_handler
