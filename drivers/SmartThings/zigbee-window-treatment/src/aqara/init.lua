local capabilities = require "st.capabilities"
local device_management = require "st.zigbee.device_management"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local utils = require "st.utils"

local initializedstate = capabilities["aqara.initializedstate"]

local opencloseDirectionPreferenceId = "aqara.opencloseDirection"
local softTouchPreferenceId = "aqara.softTouch"

local Basic = clusters.Basic
local WindowCovering = clusters.WindowCovering
local MFG_CODE = 0x115F
local PREF_ATTRIBUTE_ID = 0x0401
local SET_INIT = "setInitializedState"

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

local custom_read_attribute = function(device, cluster_id, attribute)
  local message = cluster_base.read_attribute(device, data_types.ClusterId(cluster_id), attribute)
  message.body.zcl_header.frame_ctrl:set_mfg_specific()
  message.body.zcl_header.mfg_code = data_types.validate_or_build_type(MFG_CODE, data_types.Uint16, "mfg_code")
  return message
end

local do_refresh = function(self, device)
  device:send(WindowCovering.attributes.CurrentPositionLiftPercentage:read(device))

  device:send(custom_read_attribute(device, Basic.ID, PREF_ATTRIBUTE_ID))
end

local do_configure = function(self, device)
  device:configure()

  device:send(device_management.build_bind_request(device, WindowCovering.ID, self.environment_info.hub_zigbee_eui))

  do_refresh(self, device)
end

local function device_added(driver, device)
  local main_comp = device.profile.components["main"]
  device:emit_component_event(main_comp,capabilities.windowShade.supportedWindowShadeCommands({"open", "close", "pause"}))
  device:emit_component_event(main_comp,initializedstate.supportedInitializedState({"initialize"}))

  device:send(cluster_base.write_manufacturer_specific_attribute(device, Basic.ID, PREF_ATTRIBUTE_ID, MFG_CODE,
            data_types.CharString, "\x00\x02\x00\x00\x00\x00\x00"))
  device:send(cluster_base.write_manufacturer_specific_attribute(device, Basic.ID, PREF_ATTRIBUTE_ID, MFG_CODE,
            data_types.CharString, "\x00\x08\x00\x00\x00\x00\x00"))
end

local function device_info_changed(driver, device, event, args)
  if device.preferences ~= nil then
    if device.preferences[opencloseDirectionPreferenceId] ~= args.old_st_store.preferences[opencloseDirectionPreferenceId] then
      if device.preferences[opencloseDirectionPreferenceId] == true then
        device:send(cluster_base.write_manufacturer_specific_attribute(device, Basic.ID, PREF_ATTRIBUTE_ID, MFG_CODE,
          data_types.CharString, "\x00\x02\x00\x01\x00\x00\x00"))
      else
        device:send(cluster_base.write_manufacturer_specific_attribute(device, Basic.ID, PREF_ATTRIBUTE_ID, MFG_CODE,
          data_types.CharString, "\x00\x02\x00\x00\x00\x00\x00"))
      end
    end

    if device.preferences[softTouchPreferenceId] ~= args.old_st_store.preferences[softTouchPreferenceId] then
      if device.preferences[softTouchPreferenceId] == true then
        device:send(cluster_base.write_manufacturer_specific_attribute(device, Basic.ID, PREF_ATTRIBUTE_ID, MFG_CODE,
          data_types.CharString, "\x00\x08\x00\x00\x00\x00\x00"))
      else
        device:send(cluster_base.write_manufacturer_specific_attribute(device, Basic.ID, PREF_ATTRIBUTE_ID, MFG_CODE,
          data_types.CharString, "\x00\x08\x00\x00\x00\x01\x00"))
      end
    end
  end
end

local function setInitializedState_handler(driver, device, command)
  device:set_field(SET_INIT, 'init')
  device:emit_event(initializedstate.initializedState.initializing())

  device:send(cluster_base.write_manufacturer_specific_attribute(device, Basic.ID, PREF_ATTRIBUTE_ID, MFG_CODE, 
    data_types.CharString, "\x00\x01\x00\x00\x00\x00\x00"))
  device.thread:call_with_delay(1, function(d)
    device:set_field(SET_INIT, 'close')
    device:send_to_component(command.component, WindowCovering.server.commands.GoToLiftPercentage(device, 0))
  end)
end

local function window_shade_level_cmd(driver, device, command)
  local level = command.args.shadeLevel
  device:send_to_component(command.component, WindowCovering.server.commands.GoToLiftPercentage(device, level))
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

local function motion_state_attr_handler(driver, device, value, zb_rx)
  local state = value.value
  if state == 0 then
    device:emit_event(capabilities.windowShade.windowShade.partially_open())
  elseif state == 1 then
    device:emit_event(capabilities.windowShade.windowShade.opening())
  elseif state == 2 then
    device:emit_event(capabilities.windowShade.windowShade.closing())
  end
end

local function current_position_attr_handler(driver, device, value, zb_rx)
  local level = value.value
  if level == 5.8774717541114e-39 then
    level = 0
  end
  if level > 100 then
    level = 100
  end
  level = utils.round(level)
  device:emit_event(capabilities.windowShadeLevel.shadeLevel(level))

  local lastShadeState = device:get_latest_state("main", capabilities.windowShade.ID, capabilities.windowShade.windowShade.NAME) or "unknown"
  if lastShadeState == "partially open" then
    if level == 100 then
      device:emit_event(capabilities.windowShade.windowShade.open())

      local flag = device:get_field(SET_INIT)
      if flag == 'close' then
        device:set_field(SET_INIT, 'open')
        device:send_to_component("main", WindowCovering.server.commands.GoToLiftPercentage(device, 100))
      elseif flag == 'open' then
        device:set_field(SET_INIT, 'done')
        device:send(custom_read_attribute(device, Basic.ID, PREF_ATTRIBUTE_ID))
      end
    elseif level == 0 then
      device:emit_event(capabilities.windowShade.windowShade.closed())

      local flag = device:get_field(SET_INIT)
      if flag == 'close' then
        device:set_field(SET_INIT, 'open')
        device:send_to_component("main", WindowCovering.server.commands.GoToLiftPercentage(device, 100))
      elseif flag == 'open' then
        device:set_field(SET_INIT, 'done')
        device:send(custom_read_attribute(device, Basic.ID, PREF_ATTRIBUTE_ID))
      end
    end
  end
end

local function pref_attr_handler(driver, device, value, zb_rx)
  local flag = device:get_field(SET_INIT)
  if flag == 'init' then
    device:emit_event(initializedstate.initializedState.initializing())
  elseif flag == 'close' then
    device:emit_event(initializedstate.initializedState.initializing())
  elseif flag == 'open' then
    device:emit_event(initializedstate.initializedState.initializing())
  else
    local initialized = string.byte(value.value, 3) & 0xFF
    device:emit_event(initialized  == 1 and initializedstate.initializedState.initialized() or initializedstate.initializedState.notInitialized())
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
    [initializedstate.ID] = {
      [initializedstate.commands.setInitializedState.NAME] = setInitializedState_handler
    }
  },
  zigbee_handlers = {
    attr = {
      [WindowCovering.ID] = {
        [WindowCovering.attributes.CurrentPositionLiftPercentage.ID] = current_position_attr_handler
      },
      [Basic.ID] = {
        [0x0404] = motion_state_attr_handler,
        [PREF_ATTRIBUTE_ID] = pref_attr_handler,
      },
      [0x000D] = {
        [0x0055] = current_position_attr_handler,
      }
    }
  },
  can_handle = is_aqara_products,
}

return aqara_window_treatment_handler
