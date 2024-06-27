-- Copyright 2024 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local aqara_utils = require "aqara/aqara_utils"
local FrameCtrl = require "st.zigbee.zcl.frame_ctrl"

local AnalogOutput = clusters.AnalogOutput
local WindowCovering = clusters.WindowCovering
local Groups = clusters.Groups
local MULTISTATE_CLUSTER_ID = 0x0013
local MULTISTATE_ATTRIBUTE_ID = 0x0055
local PRIVATE_HEART_BATTERY_ENERGY_ID = 0x00F7
local PRIVATE_CURTAIN_POLARITY_ATTRIBUTE_ID = 0x0400
local PRIVATE_CURTAIN_RANGE_FLAG_ATTRIBUTE_ID = 0x0402
local PRIVATE_SET_CURTAIN_SPEED_ATTRIBUTE_ID = 0x0408
local PRIVATE_STATE_OF_CHARGE_ATTRIBUTE_ID = 0x0409

local initializedStateWithGuide = capabilities["stse.initializedStateWithGuide"]
local shadeRotateState = capabilities["stse.shadeRotateState"]
local chargingStatus = capabilities["stse.chargingStatus"]
local setRotateStateCommandName = "setRotateState"

local SHADE_STATE_CLOSE = 0
local SHADE_STATE_OPEN = 1
local SHADE_STATE_STOP = 2
local ROTATE_UP_VALUE = 0x0006
local ROTATE_DOWN_VALUE = 0x0005

local function device_added(driver, device)
  device:emit_event(capabilities.windowShade.supportedWindowShadeCommands({ "open", "close", "pause" }, {visibility = {displayed = false}}))
  device:emit_event(capabilities.windowShadeLevel.shadeLevel(0))
  device:emit_event(capabilities.windowShade.windowShade.closed())
  device:emit_event(initializedStateWithGuide.initializedStateWithGuide.notInitialized())
  device:emit_event(shadeRotateState.rotateState.idle())
  device:emit_event(capabilities.battery.battery(100))
  device:emit_event(chargingStatus.chargingStatus.notCharging())
  device:emit_component_event(device.profile.components.ReverseLiftingDirection, capabilities.switch.switch.off())
  device:send(cluster_base.write_manufacturer_specific_attribute(device,
   aqara_utils.PRIVATE_CLUSTER_ID, aqara_utils.PRIVATE_ATTRIBUTE_ID, aqara_utils.MFG_CODE, data_types.Uint8, 0x01))
end

local function do_refresh(self, device)
  device:send(cluster_base.read_manufacturer_specific_attribute(device, aqara_utils.PRIVATE_CLUSTER_ID, PRIVATE_CURTAIN_POLARITY_ATTRIBUTE_ID, aqara_utils.MFG_CODE))
  device:send(cluster_base.read_manufacturer_specific_attribute(device, aqara_utils.PRIVATE_CLUSTER_ID, PRIVATE_CURTAIN_RANGE_FLAG_ATTRIBUTE_ID, aqara_utils.MFG_CODE))
  device:send(AnalogOutput.attributes.PresentValue:read(device))
end

local function do_configure(self, device)
  device:configure()
  device:send(Groups.server.commands.RemoveAllGroups(device)) -- required
  do_refresh(self, device)
end

local preference_map = {
  ["stse.adjustOperatingSpeed"] = {
    cluster_id = aqara_utils.PRIVATE_CLUSTER_ID,
    attribute_id = PRIVATE_SET_CURTAIN_SPEED_ATTRIBUTE_ID,
    mfg_code = aqara_utils.MFG_CODE,
    data_type = data_types.Uint8,
    value_map = {
      ["0"] = 0,
      ["1"] = 1,
      ["2"] = 2
    },
  },
}

local function device_info_changed(driver, device, event, args)
  local preferences = device.preferences
  local old_preferences = args.old_st_store.preferences
  if preferences ~= nil then
    for id, attr in pairs(preference_map) do
      local old_value = old_preferences[id]
      local value = preferences[id]
      if value ~= nil and value ~= old_value then
        if attr.value_map ~= nil then
          value = attr.value_map[value]
        end
        device:send(cluster_base.write_manufacturer_specific_attribute(device, attr.cluster_id, attr.attribute_id,
            attr.mfg_code, attr.data_type, value))
      end
    end
  end
end

local function shade_state_report_handler(driver, device, value, zb_rx)
  local state = value.value
  -- update state ui
  if state == SHADE_STATE_STOP then
    -- read shade position to update the UI
    device:send(AnalogOutput.attributes.PresentValue:read(device))
  elseif state == SHADE_STATE_OPEN then
    device:emit_event(capabilities.windowShade.windowShade.opening())
  elseif state == SHADE_STATE_CLOSE then
    device:emit_event(capabilities.windowShade.windowShade.closing())
  end
end

local function curtain_polarity_report_handler(driver, device, value, zb_rx)
  if value.value == false then
      device:emit_component_event(device.profile.components.ReverseLiftingDirection, capabilities.switch.switch.off())
  elseif value.value == true then
      device:emit_component_event(device.profile.components.ReverseLiftingDirection, capabilities.switch.switch.on())
  end
end

local function curtain_range_report_handler(driver, device, value, zb_rx)
  -- initializedState
  if value.value == true then
    device:emit_event(initializedStateWithGuide.initializedStateWithGuide.initialized())
  elseif value.value == false then
    device:emit_event(initializedStateWithGuide.initializedStateWithGuide.notInitialized())
  end
end

local function curtain_state_of_charge_report_handler(driver, device, value, zb_rx)
  if value.value == 1 then
    device:emit_event(chargingStatus.chargingStatus.charging())
  elseif value.value == 2 then
    device:emit_event(chargingStatus.chargingStatus.notCharging())
  elseif value.value == 3 then
    device:emit_event(chargingStatus.chargingStatus.chargingFailure())
  end
end

local function battery_energy_status_handler(driver, device, value, zb_rx)
  local battery_value = string.byte(value.value, 39) & 0xFF
  device:emit_event(capabilities.battery.battery(battery_value))
end

local function window_shade_level_cmd(driver, device, command)
  local level = command.args.shadeLevel
  -- Cannot be controlled if not initialized
  local initialized = device:get_latest_state("main", initializedStateWithGuide.ID,
    initializedStateWithGuide.initializedStateWithGuide.NAME) or 0
  if initialized == initializedStateWithGuide.initializedStateWithGuide.initialized.NAME then
    device:send(aqara_utils.custom_write_attribute(device, AnalogOutput.ID, AnalogOutput.attributes.PresentValue.ID,
      data_types.SinglePrecisionFloat, aqara_utils.SinglePrecisionFloatConversion(level), nil))
  end
end

local function window_shade_open_cmd(driver, device, command)
  -- Cannot be controlled if not initialized
  local initialized = device:get_latest_state("main", initializedStateWithGuide.ID,
    initializedStateWithGuide.initializedStateWithGuide.NAME) or 0
  if initialized == initializedStateWithGuide.initializedStateWithGuide.initialized.NAME then
    device:send(aqara_utils.custom_write_attribute(device, AnalogOutput.ID, AnalogOutput.attributes.PresentValue.ID,
      data_types.SinglePrecisionFloat, aqara_utils.SinglePrecisionFloatConversion(100), nil))
  end
end

local function window_shade_pause_cmd(driver, device, command)
  -- Cannot be controlled if not initialized
  local initialized = device:get_latest_state("main", initializedStateWithGuide.ID,
    initializedStateWithGuide.initializedStateWithGuide.NAME) or 0
  if initialized == initializedStateWithGuide.initializedStateWithGuide.initialized.NAME then
    device:send(aqara_utils.custom_write_attribute(device, MULTISTATE_CLUSTER_ID, MULTISTATE_ATTRIBUTE_ID,
    data_types.Uint16, 0x0002, nil))
  end
end

local function window_shade_close_cmd(driver, device, command)
  -- Cannot be controlled if not initialized
  local initialized = device:get_latest_state("main", initializedStateWithGuide.ID,
    initializedStateWithGuide.initializedStateWithGuide.NAME) or 0
  if initialized == initializedStateWithGuide.initializedStateWithGuide.initialized.NAME then
    device:send(aqara_utils.custom_write_attribute(device, AnalogOutput.ID, AnalogOutput.attributes.PresentValue.ID,
      data_types.SinglePrecisionFloat, aqara_utils.SinglePrecisionFloatConversion(0), nil))
  end
end

local function window_shade_dir_forward_cmd(driver, device, command)
  -- Cannot be controlled if not initialized
  local initialized = device:get_latest_state("main", initializedStateWithGuide.ID,
    initializedStateWithGuide.initializedStateWithGuide.NAME) or 0
  if initialized == initializedStateWithGuide.initializedStateWithGuide.initialized.NAME then
    device:send(cluster_base.write_manufacturer_specific_attribute(device,
      aqara_utils.PRIVATE_CLUSTER_ID, PRIVATE_CURTAIN_POLARITY_ATTRIBUTE_ID, aqara_utils.MFG_CODE, data_types.Boolean, true))
  end
end

local function window_shade_dir_reverse_cmd(driver, device, command)
  -- Cannot be controlled if not initialized
  local initialized = device:get_latest_state("main", initializedStateWithGuide.ID,
    initializedStateWithGuide.initializedStateWithGuide.NAME) or 0
  if initialized == initializedStateWithGuide.initializedStateWithGuide.initialized.NAME then
    device:send(cluster_base.write_manufacturer_specific_attribute(device,
      aqara_utils.PRIVATE_CLUSTER_ID, PRIVATE_CURTAIN_POLARITY_ATTRIBUTE_ID, aqara_utils.MFG_CODE, data_types.Boolean, false))
  end
end

local function set_rotate_command_handler(driver, device, command)
  device:emit_event(shadeRotateState.rotateState.idle({state_change = true})) -- update UI
  -- Cannot be controlled if not initialized
  local initialized = device:get_latest_state("main", initializedStateWithGuide.ID,
    initializedStateWithGuide.initializedStateWithGuide.NAME) or 0
  if initialized == initializedStateWithGuide.initializedStateWithGuide.initialized.NAME then
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
end

local aqara_roller_shade_driver_e1_handler = {
    NAME = "Aqara Roller Shade Driver E1 Handler",
    lifecycle_handlers = {
      added = device_added,
      doConfigure = do_configure,
      infoChanged = device_info_changed
    },
    zigbee_handlers = {
        attr = {
          [WindowCovering.ID] = {
            [WindowCovering.attributes.CurrentPositionLiftPercentage.ID] = function() end
          },
          [MULTISTATE_CLUSTER_ID] = {
            [MULTISTATE_ATTRIBUTE_ID] = shade_state_report_handler
          },
          [aqara_utils.PRIVATE_CLUSTER_ID] = {
            [PRIVATE_CURTAIN_POLARITY_ATTRIBUTE_ID] = curtain_polarity_report_handler,
            [PRIVATE_CURTAIN_RANGE_FLAG_ATTRIBUTE_ID] = curtain_range_report_handler,
            [PRIVATE_STATE_OF_CHARGE_ATTRIBUTE_ID] = curtain_state_of_charge_report_handler,
            [PRIVATE_HEART_BATTERY_ENERGY_ID] = battery_energy_status_handler
          },
        }
      },
    capability_handlers = {
      [capabilities.windowShadeLevel.ID] = {
        [capabilities.windowShadeLevel.commands.setShadeLevel.NAME] = window_shade_level_cmd
      },
      [capabilities.windowShade.ID] = {
        [capabilities.windowShade.commands.open.NAME] = window_shade_open_cmd,
        [capabilities.windowShade.commands.pause.NAME] = window_shade_pause_cmd,
        [capabilities.windowShade.commands.close.NAME] = window_shade_close_cmd,
      },
      [capabilities.switch.ID] = {
        [capabilities.switch.commands.on.NAME] = window_shade_dir_forward_cmd,
        [capabilities.switch.commands.off.NAME] = window_shade_dir_reverse_cmd,
      },
      [shadeRotateState.ID] = {
        [setRotateStateCommandName] = set_rotate_command_handler
      },
      [capabilities.refresh.ID] = {
        [capabilities.refresh.commands.refresh.NAME] = do_refresh
      }
    },
    can_handle = function(opts, driver, device, ...)
        return device:get_model() == "lumi.curtain.acn002"
      end
  }

return aqara_roller_shade_driver_e1_handler
