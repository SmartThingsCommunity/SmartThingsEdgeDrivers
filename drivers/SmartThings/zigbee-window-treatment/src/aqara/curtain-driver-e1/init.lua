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

local Groups = clusters.Groups
local Basic = clusters.Basic
local WindowCovering = clusters.WindowCovering
local PowerConfiguration = clusters.PowerConfiguration
local PRIVATE_CURTAIN_MANUAL_ATTRIBUTE_ID = 0x0401
local PRIVATE_CURTAIN_RANGE_FLAG_ATTRIBUTE_ID = 0x0402
local PRIVATE_CURTAIN_STATUS_ATTRIBUTE_ID = 0x0421
local PRIVATE_CURTAIN_LOCKING_SETTING_ATTRIBUTE_ID = 0x0427
local PRIVATE_CURTAIN_LOCKING_STATUS_ATTRIBUTE_ID = 0x0428

local initializedStateWithGuide = capabilities["stse.initializedStateWithGuide"]
local reverseCurtainDirection = capabilities["stse.reverseCurtainDirection"]
local hookLockState = capabilities["stse.hookLockState"]
local chargingState = capabilities["stse.chargingState"]
local softTouch = capabilities["stse.softTouch"]
local hookUnlockCommandName = "hookUnlock"
local hookLockCommandName = "hookLock"

local SHADE_STATE_CLOSE = 0
local SHADE_STATE_OPEN = 1
local SHADE_STATE_STOP = 2

local function device_added(driver, device)
  device:emit_event(capabilities.windowShade.supportedWindowShadeCommands({ "open", "close", "pause" }, {visibility = {displayed = false}}))
  device:emit_event(capabilities.windowShadeLevel.shadeLevel(0))
  device:emit_event(capabilities.windowShade.windowShade.closed())
  device:emit_event(initializedStateWithGuide.initializedStateWithGuide.notInitialized())
  device:emit_event(hookLockState.hookLockState.unlocked())
  device:emit_event(chargingState.chargingState.stopped())
  device:emit_event(capabilities.battery.battery(100))
end

local function do_refresh(self, device)
  device:send(cluster_base.read_manufacturer_specific_attribute(device, aqara_utils.PRIVATE_CLUSTER_ID, PRIVATE_CURTAIN_RANGE_FLAG_ATTRIBUTE_ID, aqara_utils.MFG_CODE))
  device:send(cluster_base.read_manufacturer_specific_attribute(device, aqara_utils.PRIVATE_CLUSTER_ID, PRIVATE_CURTAIN_LOCKING_STATUS_ATTRIBUTE_ID, aqara_utils.MFG_CODE))
  device:send(WindowCovering.attributes.CurrentPositionLiftPercentage:read(device))
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:read(device))
end

local function do_configure(self, device)
  device:configure()
  device:send(Groups.server.commands.RemoveAllGroups(device)) -- required
  do_refresh(self, device)
end

local CONFIGURATIONS = {
  {
    cluster = PowerConfiguration.ID,
    attribute = PowerConfiguration.attributes.BatteryPercentageRemaining.ID,
    minimum_interval = 30,
    maximum_interval = 3600,
    data_type = PowerConfiguration.attributes.BatteryPercentageRemaining.base_type,
    reportable_change = 1
  }
}

local function device_init(driver, device)
  for _, attribute in ipairs(CONFIGURATIONS) do
    device:add_configured_attribute(attribute)
    device:add_monitored_attribute(attribute)
  end
end

local function device_info_changed(driver, device, event, args)
  if device.preferences ~= nil then
    local reverseCurtainDirectionPrefValue = device.preferences[reverseCurtainDirection.ID]
    local softTouchPrefValue = device.preferences[softTouch.ID]

    -- reverse direction
    if reverseCurtainDirectionPrefValue ~= nil and
        reverseCurtainDirectionPrefValue ~= args.old_st_store.preferences[reverseCurtainDirection.ID] then
      local raw_value = reverseCurtainDirectionPrefValue and 0x01 or 0x00
        device:send(aqara_utils.custom_write_attribute(device, WindowCovering.ID, WindowCovering.attributes.Mode.ID,
          data_types.Bitmap8, raw_value, nil))
    end

    -- soft touch
    if softTouchPrefValue ~= nil and
        softTouchPrefValue ~= args.old_st_store.preferences[softTouch.ID] then
      device:send(cluster_base.write_manufacturer_specific_attribute(device,
        aqara_utils.PRIVATE_CLUSTER_ID, PRIVATE_CURTAIN_MANUAL_ATTRIBUTE_ID, aqara_utils.MFG_CODE, data_types.Boolean, (not softTouchPrefValue)))
    end
  end
end

local function shade_state_report_handler(driver, device, value, zb_rx)
  local state = value.value
  -- update state ui
  if state == SHADE_STATE_STOP then
    -- read shade position to update the UI
    device:send(WindowCovering.attributes.CurrentPositionLiftPercentage:read(device))
  elseif state == SHADE_STATE_OPEN then
    device:emit_event(capabilities.windowShade.windowShade.opening())
  elseif state == SHADE_STATE_CLOSE then
    device:emit_event(capabilities.windowShade.windowShade.closing())
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
  if value.value == 3 then
    device:emit_event(chargingState.chargingState.stopped())
  elseif value.value == 4 then
    device:emit_event(chargingState.chargingState.charging())
  elseif value.value == 7 then
    device:emit_event(chargingState.chargingState.fullyCharged())
  end
end

local function battery_energy_status_handler(driver, device, value, zb_rx)
  device:emit_event(capabilities.battery.battery(math.floor(value.value / 2.0 + 0.5)))
end

local function window_locking_status_handler(driver, device, value, zb_rx)
  if value.value == 0 then
    device:emit_event(hookLockState.hookLockState.unlocked())
  elseif value.value == 1 then
    device:emit_event(hookLockState.hookLockState.locked())
  elseif value.value == 2 then
    device:emit_event(hookLockState.hookLockState.locking())
  elseif value.value == 3 then
    device:emit_event(hookLockState.hookLockState.unlocking())
  end
end

local function window_shade_open_cmd(driver, device, command)
  -- Cannot be controlled if not initialized
  local initialized = device:get_latest_state("main", initializedStateWithGuide.ID,
    initializedStateWithGuide.initializedStateWithGuide.NAME) or 0
  if initialized == initializedStateWithGuide.initializedStateWithGuide.initialized.NAME then
    device:send_to_component(command.component, WindowCovering.server.commands.UpOrOpen(device))
  end
end

local function window_shade_pause_cmd(driver, device, command)
  -- Cannot be controlled if not initialized
  local initialized = device:get_latest_state("main", initializedStateWithGuide.ID,
    initializedStateWithGuide.initializedStateWithGuide.NAME) or 0
  if initialized == initializedStateWithGuide.initializedStateWithGuide.initialized.NAME then
    device:send_to_component(command.component, WindowCovering.server.commands.Stop(device))
  end
end

local function window_shade_close_cmd(driver, device, command)
  -- Cannot be controlled if not initialized
  local initialized = device:get_latest_state("main", initializedStateWithGuide.ID,
    initializedStateWithGuide.initializedStateWithGuide.NAME) or 0
  if initialized == initializedStateWithGuide.initializedStateWithGuide.initialized.NAME then
    device:send_to_component(command.component, WindowCovering.server.commands.DownOrClose(device))
  end
end

local function hook_lock_cmd(driver, device, command)
  device:send(cluster_base.write_manufacturer_specific_attribute(device,
    aqara_utils.PRIVATE_CLUSTER_ID, PRIVATE_CURTAIN_LOCKING_SETTING_ATTRIBUTE_ID, aqara_utils.MFG_CODE, data_types.Uint8, 0x01))
end

local function hook_unlock_cmd(driver, device, command)
  device:send(cluster_base.write_manufacturer_specific_attribute(device,
    aqara_utils.PRIVATE_CLUSTER_ID, PRIVATE_CURTAIN_LOCKING_SETTING_ATTRIBUTE_ID, aqara_utils.MFG_CODE, data_types.Uint8, 0x00))
end

local aqara_curtain_driver_e1_handler = {
  NAME = "Aqara Curtain Driver E1 Handler",
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    doConfigure = do_configure,
    infoChanged = device_info_changed
  },
  capability_handlers = {
    [capabilities.windowShade.ID] = {
      [capabilities.windowShade.commands.open.NAME] = window_shade_open_cmd,
      [capabilities.windowShade.commands.pause.NAME] = window_shade_pause_cmd,
      [capabilities.windowShade.commands.close.NAME] = window_shade_close_cmd,
    },
    [hookLockState.ID] = {
      [hookLockCommandName] = hook_lock_cmd,
      [hookUnlockCommandName] = hook_unlock_cmd,
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    }
  },
  zigbee_handlers = {
    attr = {
      [Basic.ID] = {
        [Basic.attributes.PowerSource.ID] = curtain_state_of_charge_report_handler
      },
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryPercentageRemaining.ID] = battery_energy_status_handler
      },
      [aqara_utils.PRIVATE_CLUSTER_ID] = {
        [PRIVATE_CURTAIN_RANGE_FLAG_ATTRIBUTE_ID] = curtain_range_report_handler,
        [PRIVATE_CURTAIN_STATUS_ATTRIBUTE_ID] = shade_state_report_handler,
        [PRIVATE_CURTAIN_LOCKING_STATUS_ATTRIBUTE_ID] = window_locking_status_handler
      }
    }
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_model() == "lumi.curtain.agl001"
  end
}

return aqara_curtain_driver_e1_handler
