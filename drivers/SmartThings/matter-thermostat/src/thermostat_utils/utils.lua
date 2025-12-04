-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local log = require "log"
local capabilities = require "st.capabilities"
local embedded_cluster_utils = require "thermostat_utils.embedded_cluster_utils"
local fields = require "thermostat_utils.fields"

local ThermostatUtils = {}

function ThermostatUtils.tbl_contains(array, value)
  if value == nil then return false end
  for _, element in pairs(array or {}) do
    if element == value then
      return true
    end
  end
  return false
end

function ThermostatUtils.get_field_for_endpoint(device, field, endpoint)
  return device:get_field(string.format("%s_%d", field, endpoint))
end

function ThermostatUtils.set_field_for_endpoint(device, field, endpoint, value, additional_params)
  device:set_field(string.format("%s_%d", field, endpoint), value, additional_params)
end

function ThermostatUtils.find_default_endpoint(device, cluster)
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

function ThermostatUtils.component_to_endpoint(device, component_name, cluster_id)
  -- Use the find_default_endpoint function to return the first endpoint that
  -- supports a given cluster.
  local component_to_endpoint_map = device:get_field(fields.COMPONENT_TO_ENDPOINT_MAP)
  if component_to_endpoint_map ~= nil and component_to_endpoint_map[component_name] ~= nil then
    return component_to_endpoint_map[component_name]
  end
  if not cluster_id then return device.MATTER_DEFAULT_ENDPOINT end
  return ThermostatUtils.find_default_endpoint(device, cluster_id)
end

function ThermostatUtils.endpoint_to_component(device, endpoint_id)
  local component_to_endpoint_map = device:get_field(fields.COMPONENT_TO_ENDPOINT_MAP)
  if component_to_endpoint_map ~= nil then
    for comp, ep in pairs(component_to_endpoint_map) do
      if ep == endpoint_id then
        return comp
      end
    end
  end
  return "main"
end

function ThermostatUtils.get_total_cumulative_energy_imported(device)
  local total_cumulative_energy_imported = device:get_field(fields.TOTAL_CUMULATIVE_ENERGY_IMPORTED_MAP) or {}
  local total_energy = 0
  for _, energyWh in pairs(total_cumulative_energy_imported) do
    total_energy = total_energy + energyWh
  end
  return total_energy
end

function ThermostatUtils.get_endpoints_by_device_type(device, device_type)
  local endpoints = {}
  for _, ep in ipairs(device.endpoints) do
    for _, dt in ipairs(ep.device_types) do
      if dt.device_type_id == device_type then
        table.insert(endpoints, ep.endpoint_id)
        break
      end
    end
  end
  table.sort(endpoints)
  return endpoints
end

function ThermostatUtils.get_device_type(device)
  -- For cases where a device has multiple device types, this list indicates which
  -- device type will be the "main" device type for purposes of selecting a profile
  -- with an appropriate category. This is done to promote consistency between
  -- devices with similar device type compositions that may report their device types
  -- listed in different orders
  local device_type_priority = {
    [fields.HEAT_PUMP_DEVICE_TYPE_ID] = 1,
    [fields.RAC_DEVICE_TYPE_ID] = 2,
    [fields.AP_DEVICE_TYPE_ID] = 3,
    [fields.THERMOSTAT_DEVICE_TYPE_ID] = 4,
    [fields.FAN_DEVICE_TYPE_ID] = 5,
    [fields.WATER_HEATER_DEVICE_TYPE_ID] = 6,
  }

  local main_device_type = false

  for _, ep in ipairs(device.endpoints) do
    if ep.device_types ~= nil then
      for _, dt in ipairs(ep.device_types) do
        if not device_type_priority[main_device_type] or (device_type_priority[dt.device_type_id] and
          device_type_priority[dt.device_type_id] < device_type_priority[main_device_type]) then
          main_device_type = dt.device_type_id
        end
      end
    end
  end

  return main_device_type
end

function ThermostatUtils.unit_conversion(value, from_unit, to_unit, capability_name)
  local conversion_function = fields.conversion_tables[from_unit] and fields.conversion_tables[from_unit][to_unit] or nil
  if not conversion_function then
    log.info_with( {hub_logs = true} , string.format("Unsupported unit conversion from %s to %s", fields.unit_strings[from_unit], fields.unit_strings[to_unit]))
    return
  end

  if not value then
    log.info_with( {hub_logs = true} , "unit conversion value is nil")
    return
  end

  return conversion_function(value, fields.molecular_weights[capability_name])
end

function ThermostatUtils.supports_capability_by_id_modular(device, capability, component)
  if not device:get_field(fields.SUPPORTED_COMPONENT_CAPABILITIES) then
    device.log.warn_with({hub_logs = true}, "Device has overriden supports_capability_by_id, but does not have supported capabilities set.")
    return false
  end
  for _, component_capabilities in ipairs(device:get_field(fields.SUPPORTED_COMPONENT_CAPABILITIES)) do
    local comp_id = component_capabilities[1]
    local capability_ids = component_capabilities[2]
    if (component == nil) or (component == comp_id) then
        for _, cap in ipairs(capability_ids) do
          if cap == capability then
            return true
          end
        end
    end
  end
  return false
end

function ThermostatUtils.report_power_consumption_to_st_energy(device, latest_total_imported_energy_wh)
  local current_time = os.time()
  local last_time = device:get_field(fields.LAST_IMPORTED_REPORT_TIMESTAMP) or 0

  -- Ensure that the previous report was sent at least 15 minutes ago
  if fields.MINIMUM_ST_ENERGY_REPORT_INTERVAL >= (current_time - last_time) then
    return
  end

  device:set_field(fields.LAST_IMPORTED_REPORT_TIMESTAMP, current_time, { persist = true })

  -- Calculate the energy delta between reports
  local energy_delta_wh = 0.0
  local previous_imported_report = device:get_latest_state("main", capabilities.powerConsumptionReport.ID,
    capabilities.powerConsumptionReport.powerConsumption.NAME)
  if previous_imported_report and previous_imported_report.energy then
    energy_delta_wh = math.max(latest_total_imported_energy_wh - previous_imported_report.energy, 0.0)
  end

  local epoch_to_iso8601 = function(time) return os.date("!%Y-%m-%dT%H:%M:%SZ", time) end

  -- Report the energy consumed during the time interval. The unit of these values should be 'Wh'
  device:emit_component_event(device.profile.components["main"], capabilities.powerConsumptionReport.powerConsumption({
    start = epoch_to_iso8601(last_time),
    ["end"] = epoch_to_iso8601(current_time - 1),
    deltaEnergy = energy_delta_wh,
    energy = latest_total_imported_energy_wh
  }))
end

return ThermostatUtils
