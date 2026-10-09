-- Copyright 2023 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local common_utils = require "common-utils"
local embedded_cluster_utils = require "embedded-cluster-utils"
local version = require "version"

local TEMPERATURE_CONTROLLED_CABINET_DEVICE_TYPE_ID = 0x0071

if version.api < 10 then
  clusters.RefrigeratorAlarm = require "RefrigeratorAlarm"
  clusters.RefrigeratorAndTemperatureControlledCabinetMode = require "RefrigeratorAndTemperatureControlledCabinetMode"
  clusters.TemperatureControl = require "TemperatureControl"
end

local SUPPORTED_REFRIGERATOR_TCC_MODES_MAP = "__supported_refrigerator_tcc_modes_map"

-- Lifecycle Handlers --
local function device_added(driver, device)
  local cabinet_eps = {}
  for _, ep in ipairs(device.endpoints) do
    for _, dt in ipairs(ep.device_types) do
      if dt.device_type_id == TEMPERATURE_CONTROLLED_CABINET_DEVICE_TYPE_ID then
        table.insert(cabinet_eps, ep.endpoint_id)
        break
      end
    end
  end

  if #cabinet_eps > 1 then
    table.sort(cabinet_eps)
    local componentToEndpointMap = { -- This is just a guess for now
      ["refrigerator"] = cabinet_eps[1],
      ["freezer"] = cabinet_eps[2]
    }
    device:set_field(common_utils.COMPONENT_TO_ENDPOINT_MAP, componentToEndpointMap, {persist = true})
  end
end

local function do_configure(driver, device)
  local tn_eps = embedded_cluster_utils.get_endpoints(device, clusters.TemperatureControl.ID, {feature_bitmap = clusters.TemperatureControl.types.Feature.TEMPERATURE_NUMBER})
  local tl_eps = embedded_cluster_utils.get_endpoints(device, clusters.TemperatureControl.ID, {feature_bitmap = clusters.TemperatureControl.types.Feature.TEMPERATURE_LEVEL})
  local profile_name = "refrigerator-freezer"
  if #tn_eps > 0 then
    profile_name = profile_name .. "-tn"
    common_utils.query_setpoint_limits(device)
  end
  if #tl_eps > 0 then
    profile_name = profile_name .. "-tl"
  end
  device.log.info_with({hub_logs=true}, string.format("Updating device profile to %s.", profile_name))
  device:try_update_metadata({profile = profile_name})
end

-- Matter Handlers --
local function temperature_setpoint_attr_handler(driver, device, ib, response)
  local component = device:endpoint_to_component(ib.endpoint_id)
  if not (component == "refrigerator" or component == "freezer") then
    device.log.warn("Not a supported device type")
    return
  end
  common_utils.temperature_setpoint_attr_handler(device, ib, component)
end

local function setpoint_limit_handler(limit_field)
  return function(driver, device, ib, response)
    local component = device:endpoint_to_component(ib.endpoint_id)
    if not (component == "refrigerator" or component == "freezer") then
      device.log.warn("Not a supported device type")
      return
    end
    common_utils.setpoint_limit_handler(device, ib, limit_field, component)
  end
end

local function refrigerator_tcc_supported_modes_attr_handler(driver, device, ib, response)
  local supportedRefrigeratorTccModesMap = device:get_field(SUPPORTED_REFRIGERATOR_TCC_MODES_MAP) or {}
  local supportedRefrigeratorTccModes = {}
  for _, mode in ipairs(ib.data.elements) do
    if version.api < 10 then
      clusters.RefrigeratorAndTemperatureControlledCabinetMode.types.ModeOptionStruct:augment_type(mode)
    end
    table.insert(supportedRefrigeratorTccModes, mode.elements.label.value)
  end
  supportedRefrigeratorTccModesMap[ib.endpoint_id] = supportedRefrigeratorTccModes
  device:set_field(SUPPORTED_REFRIGERATOR_TCC_MODES_MAP, supportedRefrigeratorTccModesMap, {persist = true})
  local event = capabilities.mode.supportedModes(supportedRefrigeratorTccModes, {visibility = {displayed = false}})
  device:emit_event_for_endpoint(ib.endpoint_id, event)
  event = capabilities.mode.supportedArguments(supportedRefrigeratorTccModes, {visibility = {displayed = false}})
  device:emit_event_for_endpoint(ib.endpoint_id, event)
end

local function refrigerator_tcc_mode_attr_handler(driver, device, ib, response)
  local supportedRefrigeratorTccModesMap = device:get_field(SUPPORTED_REFRIGERATOR_TCC_MODES_MAP)
  local supportedRefrigeratorTccModes = supportedRefrigeratorTccModesMap[ib.endpoint_id] or {}
  local currentMode = ib.data.value
  for i, mode in ipairs(supportedRefrigeratorTccModes) do
    if i - 1 == currentMode then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.mode.mode(mode))
      break
    end
  end
end

local function refrigerator_alarm_attr_handler(driver, device, ib, response)
  if ib.data.value & clusters.RefrigeratorAlarm.types.AlarmMap.DOOR_OPEN > 0 then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.contactSensor.contact.open())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.contactSensor.contact.closed())
  end
end

-- Capability Handlers --
local function handle_refrigerator_tcc_mode(driver, device, cmd)
  local ep = device:component_to_endpoint(cmd.component)
  local supportedRefrigeratorTccModesMap = device:get_field(SUPPORTED_REFRIGERATOR_TCC_MODES_MAP)
  local supportedRefrigeratorTccModes = supportedRefrigeratorTccModesMap[ep] or {}
  for i, mode in ipairs(supportedRefrigeratorTccModes) do
    if cmd.args.mode == mode then
      device:send(clusters.RefrigeratorAndTemperatureControlledCabinetMode.commands.ChangeToMode(device, ep, i - 1))
      return
    end
  end
end

local function handle_temperature_setpoint(driver, device, cmd)
  common_utils.handle_temperature_setpoint(device, cmd, cmd.component)
end

local matter_refrigerator_handler = {
  NAME = "matter-refrigerator",
  lifecycle_handlers = {
    added = device_added,
    doConfigure = do_configure
  },
  matter_handlers = {
    attr = {
      [clusters.TemperatureControl.ID] = {
        [clusters.TemperatureControl.attributes.TemperatureSetpoint.ID] = temperature_setpoint_attr_handler,
        [clusters.TemperatureControl.attributes.MinTemperature.ID] = setpoint_limit_handler(common_utils.setpoint_limit_device_field.MIN_TEMP),
        [clusters.TemperatureControl.attributes.MaxTemperature.ID] = setpoint_limit_handler(common_utils.setpoint_limit_device_field.MAX_TEMP)
      },
      [clusters.RefrigeratorAndTemperatureControlledCabinetMode.ID] = {
        [clusters.RefrigeratorAndTemperatureControlledCabinetMode.attributes.SupportedModes.ID] = refrigerator_tcc_supported_modes_attr_handler,
        [clusters.RefrigeratorAndTemperatureControlledCabinetMode.attributes.CurrentMode.ID] = refrigerator_tcc_mode_attr_handler
      },
      [clusters.RefrigeratorAlarm.ID] = {
        [clusters.RefrigeratorAlarm.attributes.State.ID] = refrigerator_alarm_attr_handler
      }
    }
  },
  capability_handlers = {
    [capabilities.mode.ID] = {
      [capabilities.mode.commands.setMode.NAME] = handle_refrigerator_tcc_mode
    },
    [capabilities.temperatureSetpoint.ID] = {
      [capabilities.temperatureSetpoint.commands.setTemperatureSetpoint.NAME] = handle_temperature_setpoint
    }
  },
  can_handle = require("matter-refrigerator.can_handle"),
}

return matter_refrigerator_handler
