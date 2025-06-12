-- Copyright 2023 SmartThings
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
local clusters = require "st.matter.clusters"
local common_utils = require "common-utils"
local embedded_cluster_utils = require "embedded-cluster-utils"
local log = require "log"
local utils = require "st.utils"
local version = require "version"

local REFRIGERATOR_DEVICE_TYPE_ID = 0x0070
local TEMPERATURE_CONTROLLED_CABINET_DEVICE_TYPE_ID = 0x0071

if version.api < 10 then
  clusters.RefrigeratorAlarm = require "RefrigeratorAlarm"
  clusters.RefrigeratorAndTemperatureControlledCabinetMode = require "RefrigeratorAndTemperatureControlledCabinetMode"
  clusters.TemperatureControl = require "TemperatureControl"
end

local SUPPORTED_REFRIGERATOR_TCC_MODES_MAP = "__supported_refrigerator_tcc_modes_map"

-- For RPC version <= 5, this is a work around to handle when units for temperatureSetpoint is changed for the App.
-- When units are switched, we will never know the units of the received command value as the arguments don't contain the unit.
-- So to handle this we assume the following ranges considering usual refrigerator temperatures:
-- Refrigerator:
--   1. if the received setpoint command value is in range -6 ~ 20, it is inferred as *C
--   2. if the received setpoint command value is in range 21.2 ~ 68, it is inferred as *F
-- Freezer:
--   1. if the received setpoint command value is in range -24 ~ -12, it is inferred as *C
--   2. if the received setpoint command value is in range -11.2 ~ 10.4, it is inferred as *F
-- For RPC version >= 6, we can always assume that the values received from temperatureSetpoint
-- is in Celsius, but we still limit the setpoint range to reasonable values.
local REFRIGERATOR_MAX_TEMP_IN_C = version.rpc >= 6 and 30.0 or 20.0
local REFRIGERATOR_MIN_TEMP_IN_C = version.rpc >= 6 and -10.0 or -6.0
local FREEZER_MAX_TEMP_IN_C = version.rpc >= 6 and 0.0 or -12.0
local FREEZER_MIN_TEMP_IN_C = version.rpc >= 6 and -30.0 or -24.0

local function is_matter_refrigerator(opts, driver, device)
  for _, ep in ipairs(device.endpoints) do
    for _, dt in ipairs(ep.device_types) do
      if dt.device_type_id == REFRIGERATOR_DEVICE_TYPE_ID then
        return true
      end
    end
  end
  return false
end

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

  table.sort(cabinet_eps)

  if #cabinet_eps > 1 then
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
  if not common_utils.supports_temperature_number_endpoint(device, ib.endpoint_id) then
    return
  end
  device.log.info(string.format("temperature_setpoint_attr_handler: %d", ib.data.value))
  local min_field = string.format("%s-%d", common_utils.setpoint_limit_device_field.MIN_TEMP, ib.endpoint_id)
  local max_field = string.format("%s-%d", common_utils.setpoint_limit_device_field.MAX_TEMP, ib.endpoint_id)
  local min, max
  local component = device:endpoint_to_component(ib.endpoint_id)
  if component == "refrigerator" then
    min = device:get_field(min_field) or REFRIGERATOR_MIN_TEMP_IN_C
    max = device:get_field(max_field) or REFRIGERATOR_MAX_TEMP_IN_C
  elseif component == "freezer" then
    min = device:get_field(min_field) or FREEZER_MIN_TEMP_IN_C
    max = device:get_field(max_field) or FREEZER_MAX_TEMP_IN_C
  else
    device.log.warn(string.format("Not a supported device type"))
    return
  end
  local temp = ib.data.value / 100.0
  local unit = "C"
  local range = {
    minimum = min,
    maximum = max,
    step = 0.1
  }

  -- Only emit the capability for RPC version >= 5, since unit conversion for
  -- range capabilities is only supported in that case.
  if version.rpc >= 5 then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.temperatureSetpoint.temperatureSetpointRange({value = range, unit = unit}), { visibility = { displayed = false } })
  end

  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.temperatureSetpoint.temperatureSetpoint({value = temp, unit = unit}))
end

local function setpoint_limit_handler(limit_field)
  return function(driver, device, ib, response)
    if not common_utils.supports_temperature_number_endpoint(device, ib.endpoint_id) then
      return
    end
    local field = string.format("%s-%d", limit_field, ib.endpoint_id)
    local val = ib.data.value / 100.0

    local min_temp_in_c, max_temp_in_c
    local component = device:endpoint_to_component(ib.endpoint_id)
    if component == "refrigerator" then
      min_temp_in_c = REFRIGERATOR_MIN_TEMP_IN_C
      max_temp_in_c = REFRIGERATOR_MAX_TEMP_IN_C
    elseif component == "freezer" then
      min_temp_in_c =  FREEZER_MIN_TEMP_IN_C
      max_temp_in_c =  FREEZER_MAX_TEMP_IN_C
    else
      device.log.warn(string.format("Not a supported device type"))
      return
    end

    val = utils.clamp_value(val, min_temp_in_c, max_temp_in_c)

    device.log.info("Setting " .. field .. " to " .. string.format("%s", val))
    device:set_field(field, val, { persist = true })
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
  device.log.info_with({ hub_logs = true },
    string.format("refrigerator_tcc_mode_attr_handler currentMode: %s", ib.data.value))

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
  device.log.info(string.format("handle_refrigerator_tcc_mode mode: %s", cmd.args.mode))
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
  local ep = device:component_to_endpoint(cmd.component)
  if not common_utils.supports_temperature_number_endpoint(device, ep) then
    return
  end
  device.log.info(string.format("handle_temperature_setpoint: %s", cmd.args.setpoint))

  local value = cmd.args.setpoint
  local _, temp_setpoint = device:get_latest_state(
    cmd.component, capabilities.temperatureSetpoint.ID,
    capabilities.temperatureSetpoint.temperatureSetpoint.NAME,
    0, { value = 0, unit = "C" }
  )
  local min_field = string.format("%s-%d", common_utils.setpoint_limit_device_field.MIN_TEMP, ep)
  local max_field = string.format("%s-%d", common_utils.setpoint_limit_device_field.MAX_TEMP, ep)
  local min, max
  local max_temp_in_c
  local component = cmd.component
  if component == "refrigerator" then
    min = device:get_field(min_field) or REFRIGERATOR_MIN_TEMP_IN_C
    max = device:get_field(max_field) or REFRIGERATOR_MAX_TEMP_IN_C
    max_temp_in_c = REFRIGERATOR_MAX_TEMP_IN_C
  elseif component == "freezer" then
    min = device:get_field(min_field) or FREEZER_MIN_TEMP_IN_C
    max = device:get_field(max_field) or FREEZER_MAX_TEMP_IN_C
    max_temp_in_c = FREEZER_MAX_TEMP_IN_C
  else
    device.log.warn(string.format("Not a supported device type"))
    return
  end

  if version.rpc <= 5 and value > max_temp_in_c then
    value = utils.f_to_c(value)
  end
  if value < min or value > max then
    log.warn(string.format(
      "Invalid setpoint (%s) outside the min (%s) and the max (%s)",
      value, min, max
    ))
    device:emit_event_for_endpoint(ep, capabilities.temperatureSetpoint.temperatureSetpoint(temp_setpoint))
    return
  end

  ep = device:component_to_endpoint(cmd.component)
  device:send(clusters.TemperatureControl.commands.SetTemperature(device, ep, utils.round(value * 100), nil))
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
  can_handle = is_matter_refrigerator
}

return matter_refrigerator_handler
