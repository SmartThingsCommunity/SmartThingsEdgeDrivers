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
local log = require "log"
local clusters = require "st.matter.clusters"
local embedded_cluster_utils = require "embedded-cluster-utils"
local MatterDriver = require "st.matter.driver"

local IS_LOCAL_OVERRIDE = "__is_local_override"
-- Per matter spec, the pump level is in steps of 0.5% and the
-- max level value is 200. Anything above is considered 100%
local MAX_PUMP_ATTR_LEVEL = 200
local MAX_CAP_SWITCH_LEVEL = 100

-- Include driver-side definitions when lua libs api version is < 10
local version = require "version"
if version.api < 10 then
  clusters.PumpConfigurationAndControl = require "PumpConfigurationAndControl"
end

local pumpOperationMode = capabilities.pumpOperationMode
local pumpControlMode = capabilities.pumpControlMode

local PUMP_OPERATION_MODE_MAP = {
  [clusters.PumpConfigurationAndControl.types.OperationModeEnum.NORMAL]  = pumpOperationMode.operationMode.normal,
  [clusters.PumpConfigurationAndControl.types.OperationModeEnum.MINIMUM] = pumpOperationMode.operationMode.minimum,
  [clusters.PumpConfigurationAndControl.types.OperationModeEnum.MAXIMUM] = pumpOperationMode.operationMode.maximum,
  [clusters.PumpConfigurationAndControl.types.OperationModeEnum.LOCAL]   = pumpOperationMode.operationMode.localSetting,
}

local PUMP_CONTROL_MODE_MAP = {
  [clusters.PumpConfigurationAndControl.types.ControlModeEnum.CONSTANT_SPEED]         = pumpControlMode.controlMode.constantSpeed,
  [clusters.PumpConfigurationAndControl.types.ControlModeEnum.CONSTANT_PRESSURE]      = pumpControlMode.controlMode.constantPressure,
  [clusters.PumpConfigurationAndControl.types.ControlModeEnum.PROPORTIONAL_PRESSURE]  = pumpControlMode.controlMode.proportionalPressure,
  [clusters.PumpConfigurationAndControl.types.ControlModeEnum.CONSTANT_FLOW]          = pumpControlMode.controlMode.constantFlow,
  [clusters.PumpConfigurationAndControl.types.ControlModeEnum.CONSTANT_TEMPERATURE]   = pumpControlMode.controlMode.constantTemperature,
  [clusters.PumpConfigurationAndControl.types.ControlModeEnum.AUTOMATIC]              = pumpControlMode.controlMode.automatic,
}

local PUMP_CURRENT_CONTROL_MODE_MAP = {
  [clusters.PumpConfigurationAndControl.types.ControlModeEnum.CONSTANT_SPEED]         = pumpControlMode.currentControlMode.constantSpeed,
  [clusters.PumpConfigurationAndControl.types.ControlModeEnum.CONSTANT_PRESSURE]      = pumpControlMode.currentControlMode.constantPressure,
  [clusters.PumpConfigurationAndControl.types.ControlModeEnum.PROPORTIONAL_PRESSURE]  = pumpControlMode.currentControlMode.proportionalPressure,
  [clusters.PumpConfigurationAndControl.types.ControlModeEnum.CONSTANT_FLOW]          = pumpControlMode.currentControlMode.constantFlow,
  [clusters.PumpConfigurationAndControl.types.ControlModeEnum.CONSTANT_TEMPERATURE]   = pumpControlMode.currentControlMode.constantTemperature,
  [clusters.PumpConfigurationAndControl.types.ControlModeEnum.AUTOMATIC]              = pumpControlMode.currentControlMode.automatic,
}

local subscribed_attributes = {
  [capabilities.switch.ID] = {
    clusters.OnOff.attributes.OnOff,
  },
  [capabilities.switchLevel.ID] = {
    clusters.LevelControl.attributes.CurrentLevel
  },
  [capabilities.pumpOperationMode.ID]={
    clusters.PumpConfigurationAndControl.attributes.OperationMode,
    clusters.PumpConfigurationAndControl.attributes.EffectiveOperationMode,
    clusters.PumpConfigurationAndControl.attributes.PumpStatus,
  },
  [capabilities.pumpControlMode.ID]={
    clusters.PumpConfigurationAndControl.attributes.EffectiveControlMode,
  },
}

local function find_default_endpoint(device, cluster)
  local res = device.MATTER_DEFAULT_ENDPOINT
  local eps = embedded_cluster_utils.get_endpoints(device, cluster)
  table.sort(eps)
  for _, v in ipairs(eps) do
    if v ~= 0 then --0 is the matter RootNode endpoint
      return v
    end
  end
  device.log.warn(string.format("Did not find default endpoint, will use endpoint %d instead", device.MATTER_DEFAULT_ENDPOINT))
  return res
end

local function component_to_endpoint(device, component_name)
  -- Use the find_default_endpoint function to return the first endpoint that
  -- supports a given cluster.
  return find_default_endpoint(device, clusters.PumpConfigurationAndControl.ID)
end

local function device_init(driver, device)
  device:subscribe()
  device:set_component_to_endpoint_fn(component_to_endpoint)
end

local function info_changed(driver, device, event, args)
  --Note this is needed because device:subscribe() does not recalculate
  -- the subscribed attributes each time it is run, that only happens at init.
  -- This will change in the 0.48.x release of the lua libs.
  for cap_id, attributes in pairs(subscribed_attributes) do
    if device:supports_capability_by_id(cap_id) then
      for _, attr in ipairs(attributes) do
        device:add_subscribed_attribute(attr)
      end
    end
  end
  device:subscribe()
end

local function set_supported_op_mode(driver, device)
  local spd_eps = embedded_cluster_utils.get_endpoints(device, clusters.PumpConfigurationAndControl.ID, {feature_bitmap = clusters.PumpConfigurationAndControl.types.Feature.CONSTANT_SPEED})
  local local_eps = embedded_cluster_utils.get_endpoints(device, clusters.PumpConfigurationAndControl.ID, {feature_bitmap = clusters.PumpConfigurationAndControl.types.Feature.LOCAL_OPERATION})
  local supported_op_modes = {pumpOperationMode.operationMode.normal.NAME}
  if #spd_eps > 0 then
    table.insert(supported_op_modes, pumpOperationMode.operationMode.minimum.NAME)
    table.insert(supported_op_modes, pumpOperationMode.operationMode.maximum.NAME)
  end
  if #local_eps > 0 then
    table.insert(supported_op_modes, pumpOperationMode.operationMode.localSetting.NAME)
  end
  device:emit_event(pumpOperationMode.supportedOperationModes(supported_op_modes))
end

local function set_supported_control_mode(driver, device)
  local spd_eps = embedded_cluster_utils.get_endpoints(device, clusters.PumpConfigurationAndControl.ID, {feature_bitmap = clusters.PumpConfigurationAndControl.types.Feature.CONSTANT_SPEED})
  local prsconst_eps = embedded_cluster_utils.get_endpoints(device, clusters.PumpConfigurationAndControl.ID, {feature_bitmap = clusters.PumpConfigurationAndControl.types.Feature.CONSTANT_PRESSURE})
  local prscomp_eps = embedded_cluster_utils.get_endpoints(device, clusters.PumpConfigurationAndControl.ID, {feature_bitmap = clusters.PumpConfigurationAndControl.types.Feature.COMPENSATED_PRESSURE})
  local flw_eps = embedded_cluster_utils.get_endpoints(device, clusters.PumpConfigurationAndControl.ID, {feature_bitmap = clusters.PumpConfigurationAndControl.types.Feature.CONSTANT_FLOW})
  local temp_eps = embedded_cluster_utils.get_endpoints(device, clusters.PumpConfigurationAndControl.ID, {feature_bitmap = clusters.PumpConfigurationAndControl.types.Feature.CONSTANT_TEMPERATURE})
  local auto_eps = embedded_cluster_utils.get_endpoints(device, clusters.PumpConfigurationAndControl.ID, {feature_bitmap = clusters.PumpConfigurationAndControl.types.Feature.AUTOMATIC})
  local supported_control_modes = {}
  if #spd_eps > 0 then
    table.insert(supported_control_modes, pumpControlMode.controlMode.constantSpeed.NAME)
  end
  if #prsconst_eps > 0 then
    table.insert(supported_control_modes, pumpControlMode.controlMode.constantPressure.NAME)
  end
  if #prscomp_eps > 0 then
    table.insert(supported_control_modes, pumpControlMode.controlMode.proportionalPressure.NAME)
  end
  if #flw_eps > 0 then
    table.insert(supported_control_modes, pumpControlMode.controlMode.constantFlow.NAME)
  end
  if #temp_eps > 0 then
    table.insert(supported_control_modes, pumpControlMode.controlMode.constantTemperature.NAME)
  end
  if #auto_eps > 0 then
    table.insert(supported_control_modes, pumpControlMode.controlMode.automatic.NAME)
  end
  device:emit_event(pumpControlMode.supportedControlModes(supported_control_modes))
end

local function do_configure(driver, device)
  local pump_eps = embedded_cluster_utils.get_endpoints(device, clusters.PumpConfigurationAndControl.ID)
  local level_eps = embedded_cluster_utils.get_endpoints(device, clusters.LevelControl.ID)
  local profile_name = "pump"
  if #pump_eps == 1 then
    if #level_eps > 0 then
      profile_name = profile_name .. "-level"
    else
      profile_name = profile_name .. "-only"
    end
    device.log.info_with({hub_logs=true}, string.format("Updating device profile to %s.", profile_name))
    device:try_update_metadata({profile = profile_name})
  else
    device.log.warn_with({hub_logs=true}, "Device does not support pump configuration and control cluster")
  end
  set_supported_op_mode(driver, device)
  set_supported_control_mode(driver, device)
end

-- Matter Handlers --
local function on_off_attr_handler(driver, device, ib, response)
  if ib.data.value then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switch.switch.on())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switch.switch.off())
  end
end

local function level_attr_handler(driver, device, ib, response)
  if ib.data.value ~= nil then
    local level = math.floor((ib.data.value / MAX_PUMP_ATTR_LEVEL * MAX_CAP_SWITCH_LEVEL) + 0.5)
    level = math.min(level, MAX_CAP_SWITCH_LEVEL)
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switchLevel.level(level))
  end
end

local function effective_operation_mode_handler(driver, device, ib, response)
  local modeEnum = clusters.PumpConfigurationAndControl.types.OperationModeEnum
  local supported_control_modes = {}
  local local_override = device:get_field(IS_LOCAL_OVERRIDE)
  if not local_override then
    set_supported_op_mode(driver, device)
  end
  if ib.data.value == modeEnum.NORMAL then
    device:emit_event_for_endpoint(ib.endpoint_id, pumpOperationMode.currentOperationMode.normal())
    set_supported_control_mode(driver, device)
  elseif ib.data.value == modeEnum.MINIMUM then
    device:emit_event_for_endpoint(ib.endpoint_id, pumpOperationMode.currentOperationMode.minimum())
    device:emit_event_for_endpoint(ib.endpoint_id, pumpControlMode.supportedControlModes(supported_control_modes))
  elseif ib.data.value == modeEnum.MAXIMUM then
    device:emit_event_for_endpoint(ib.endpoint_id, pumpOperationMode.currentOperationMode.maximum())
    device:emit_event_for_endpoint(ib.endpoint_id, pumpControlMode.supportedControlModes(supported_control_modes))
  elseif ib.data.value == modeEnum.LOCAL then
    device:emit_event_for_endpoint(ib.endpoint_id, pumpOperationMode.currentOperationMode.localSetting())
    device:emit_event_for_endpoint(ib.endpoint_id, pumpControlMode.supportedControlModes(supported_control_modes))
  end
end

local function effective_control_mode_handler(driver, device, ib, response)
  device:emit_event_for_endpoint(ib.endpoint_id, PUMP_CURRENT_CONTROL_MODE_MAP[ib.data.value]())
end

local function pump_status_handler(driver, device, ib, response)
  if ib.data.value == clusters.PumpConfigurationAndControl.types.PumpStatusBitmap.LOCAL_OVERRIDE then
    device:set_field(IS_LOCAL_OVERRIDE, true, {persist = true})
    device:emit_event_for_endpoint(ib.endpoint_id, pumpOperationMode.currentOperationMode.localSetting())
    local supported_op_modes = {}
    local supported_control_modes = {}
    device:emit_event(pumpOperationMode.supportedOperationModes(supported_op_modes))
    device:emit_event(pumpControlMode.supportedControlModes(supported_control_modes))
  elseif ib.data.value == clusters.PumpConfigurationAndControl.types.PumpStatusBitmap.RUNNING then
    device:set_field(IS_LOCAL_OVERRIDE, false, {persist = true})
    device:send(clusters.PumpConfigurationAndControl.attributes.EffectiveOperationMode:read(device))
  end
end

-- Capability Handlers --
local function handle_switch_on(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local req = clusters.OnOff.server.commands.On(device, endpoint_id)
  device:send(req)
end

local function handle_switch_off(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local req = clusters.OnOff.server.commands.Off(device, endpoint_id)
  device:send(req)
end

local function handle_set_level(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local level = math.floor(cmd.args.level / MAX_CAP_SWITCH_LEVEL * MAX_PUMP_ATTR_LEVEL)
  local req = clusters.LevelControl.server.commands.MoveToLevelWithOnOff(device, endpoint_id, level, cmd.args.rate or 0, 0 ,0)
  device:send(req)
end

local function set_operation_mode(driver, device, cmd)
  local mode_id = nil
  for id, mode in pairs(PUMP_OPERATION_MODE_MAP) do
    if mode.NAME == cmd.args.operationMode then
      mode_id = id
      break
    end
  end
  if mode_id then
    device:send(clusters.PumpConfigurationAndControl.attributes.OperationMode:write(device, device:component_to_endpoint(cmd.component), mode_id))
  end
end

local function set_control_mode(driver, device, cmd)
  local mode_id = nil
  for id, mode in pairs(PUMP_CONTROL_MODE_MAP) do
    if mode.NAME == cmd.args.controlMode then
      mode_id = id
      break
    end
  end
  if mode_id then
    device:send(clusters.PumpConfigurationAndControl.attributes.ControlMode:write(device, device:component_to_endpoint(cmd.component), mode_id))
  end
end

local matter_driver_template = {
  lifecycle_handlers = {
    init = device_init,
    doConfigure = do_configure,
    infoChanged = info_changed,
  },
  matter_handlers = {
    attr = {
      [clusters.OnOff.ID] = {
        [clusters.OnOff.attributes.OnOff.ID] = on_off_attr_handler,
      },
      [clusters.LevelControl.ID] = {
        [clusters.LevelControl.attributes.CurrentLevel.ID] = level_attr_handler
      },
      [clusters.PumpConfigurationAndControl.ID] = {
        [clusters.PumpConfigurationAndControl.attributes.EffectiveOperationMode.ID] = effective_operation_mode_handler,
        [clusters.PumpConfigurationAndControl.attributes.EffectiveControlMode.ID] = effective_control_mode_handler,
        [clusters.PumpConfigurationAndControl.attributes.PumpStatus.ID] = pump_status_handler,
      },
    },
  },
  subscribed_attributes = subscribed_attributes,
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = handle_switch_on,
      [capabilities.switch.commands.off.NAME] = handle_switch_off,
    },
    [capabilities.switchLevel.ID] = {
      [capabilities.switchLevel.commands.setLevel.NAME] = handle_set_level,
    },
    [capabilities.pumpOperationMode.ID] = {
      [capabilities.pumpOperationMode.commands.setOperationMode.NAME] = set_operation_mode,
    },
    [capabilities.pumpControlMode.ID] = {
      [capabilities.pumpControlMode.commands.setControlMode.NAME] = set_control_mode,
    },
  },
  supported_capabilities = {
    capabilities.switch,
    capabilities.switchLevel,
    capabilities.pumpOperationMode,
    capabilities.pumpControlMode,
  },
}

local matter_driver = MatterDriver("matter-pump", matter_driver_template)
log.info_with({hub_logs=true}, string.format("Starting %s driver, with dispatcher: %s", matter_driver.NAME, matter_driver.matter_dispatcher))
matter_driver:run()