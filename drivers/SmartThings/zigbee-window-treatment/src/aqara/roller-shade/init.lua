local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local utils = require "st.utils"
local aqara_utils = require "aqara/aqara_utils"
local log = require "log"

local Basic = clusters.Basic
local AnalogOutput = clusters.AnalogOutput
local Groups = clusters.Groups

local function set_initialized_state_handler(driver, device, command)
  log.debug("-----------> set_initialized_state_handler " .. command.component)
end

local function shade_state_attr_handler(driver, device, value, zb_rx)
  aqara_utils.shade_state_changed(device, value)
end

local function current_position_attr_handler(driver, device, value, zb_rx)
  aqara_utils.shade_position_changed(device, value)
end

local function pref_attr_handler(driver, device, value, zb_rx)
  local initialized = string.byte(value.value, 3) & 0xFF
  device:emit_event(initialized == 1 and aqara_utils.deviceInitialization.initializedState.initialized() or
    aqara_utils.deviceInitialization.initializedState.notInitialized())
end

local function do_refresh(self, device)
  device:send(AnalogOutput.attributes.PresentValue:read(device))

  aqara_utils.read_pref_attribute(device)
end

local function device_info_changed(driver, device, event, args)
  if device.preferences ~= nil then
    aqara_utils.write_reverse_preferences(device, args)
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
