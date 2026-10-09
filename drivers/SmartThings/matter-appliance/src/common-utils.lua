-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local embedded_cluster_utils = require "embedded-cluster-utils"
local im = require "st.matter.interaction_model"
local utils = require "st.utils"
local version = require "version"

local extended_range_support = version.rpc >= 6

-- For RPC version <= 5, temperature conversion for setpoint ranges is not supported. When units are switched,
-- the units of the received command are unknown as the arguments don't contain the unit. To handle this, we
-- use a smaller range so that the temperature ranges for Celsius and Fahrenheit are separate. Take the laundry
-- washer range for example:
--   if the received setpoint command value is in range 13 ~ 55, it is inferred as *C
--   if the received setpoint command value is in range 55.4 ~ 131, it is inferred as *F
-- For RPC version >= 6, we can always assume that the values received from temperatureSetpoint are in Celsius,
-- so we can support a larger setpoint range, but we still limit the range to reasonable values.
local default_min_and_max_temp_by_device_type = {
  ["dishwasher"] =   { min_temp = extended_range_support and 0.0 or 33.0,    max_temp = extended_range_support and 100.0 or 90.0 },
  ["dryer"] =        { min_temp = extended_range_support and 0.0 or 27.0,    max_temp = extended_range_support and 100.0 or 80.0 },
  ["washer"] =       { min_temp = extended_range_support and 0.0 or 13.0,    max_temp = extended_range_support and 100.0 or 55.0 },
  ["oven"] =         { min_temp = extended_range_support and 0.0 or 127.0,   max_temp = extended_range_support and 400.0 or 260.0 },
  ["refrigerator"] = { min_temp = extended_range_support and -10.0 or -6.0,  max_temp = extended_range_support and 30.0 or 20.0 },
  ["freezer"] =      { min_temp = extended_range_support and -30.0 or -24.0, max_temp = extended_range_support and 0.0 or -12.0 },
  ["default"] =      { min_temp = 0.0,                                       max_temp = extended_range_support and 100.0 or 40.0 }
}

local common_utils = {}

common_utils.COMPONENT_TO_ENDPOINT_MAP = "__component_to_endpoint_map"
common_utils.SUPPORTED_TEMPERATURE_LEVELS_MAP = "__supported_temperature_levels_map"

common_utils.updated_fields = {
  { current_field_name = "__supported_temperature_levels", updated_field_name = common_utils.SUPPORTED_TEMPERATURE_LEVELS_MAP }
}

common_utils.setpoint_limit_device_field = {
  MIN_TEMP = "MIN_TEMP",
  MAX_TEMP = "MAX_TEMP"
}

function common_utils.check_field_name_updates(device)
  for _, field in ipairs(common_utils.updated_fields) do
    if device:get_field(field.current_field_name) then
      if field.updated_field_name ~= nil then
        device:set_field(field.updated_field_name, device:get_field(field.current_field_name), {persist = true})
      end
      device:set_field(field.current_field_name, nil)
    end
  end
end

function common_utils.get_endpoints_for_dt(device, device_type)
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

function common_utils.query_setpoint_limits(device)
  local setpoint_limit_read = im.InteractionRequest(im.InteractionRequest.RequestType.READ, {})
  if device:get_field(common_utils.setpoint_limit_device_field.MIN_TEMP) == nil then
    setpoint_limit_read:merge(clusters.TemperatureControl.attributes.MinTemperature:read())
  end
  if device:get_field(common_utils.setpoint_limit_device_field.MAX_TEMP) == nil then
    setpoint_limit_read:merge(clusters.TemperatureControl.attributes.MaxTemperature:read())
  end
  if #setpoint_limit_read.info_blocks ~= 0 then
    device:send(setpoint_limit_read)
  end
end

function common_utils.supports_temperature_level_endpoint(device, endpoint)
  local feature = clusters.TemperatureControl.types.Feature.TEMPERATURE_LEVEL
  local tl_eps = embedded_cluster_utils.get_endpoints(device, clusters.TemperatureControl.ID, {feature_bitmap = feature})
  if #tl_eps == 0 then
    device.log.warn(string.format("Device does not support TEMPERATURE_LEVEL feature"))
    return false
  end
  for _, eps in ipairs(tl_eps) do
    if eps == endpoint then
      return true
    end
  end
  device.log.warn(string.format("Endpoint(%d) does not support TEMPERATURE_LEVEL feature", endpoint))
  return false
end

function common_utils.supports_temperature_number_endpoint(device, endpoint)
  local feature = clusters.TemperatureControl.types.Feature.TEMPERATURE_NUMBER
  local tn_eps = embedded_cluster_utils.get_endpoints(device, clusters.TemperatureControl.ID, {feature_bitmap = feature})
  if #tn_eps == 0 then
    device.log.warn(string.format("Device does not support TEMPERATURE_NUMBER feature"))
    return false
  end
  for _, eps in ipairs(tn_eps) do
    if eps == endpoint then
      return true
    end
  end
  device.log.warn(string.format("Endpoint(%d) does not support TEMPERATURE_NUMBER feature", endpoint))
  return false
end

function common_utils.temperature_setpoint_attr_handler(device, ib, device_type)
  local min = device:get_field(string.format("%s-%d", common_utils.setpoint_limit_device_field.MIN_TEMP, ib.endpoint_id))
    or default_min_and_max_temp_by_device_type[device_type].min_temp
  local max = device:get_field(string.format("%s-%d", common_utils.setpoint_limit_device_field.MAX_TEMP, ib.endpoint_id))
    or default_min_and_max_temp_by_device_type[device_type].max_temp
  if not min or not max or not common_utils.supports_temperature_number_endpoint(device, ib.endpoint_id) then return end
  local temp = ib.data.value / 100.0
  local unit = "C"
  local range = { minimum = min, maximum = max, step = 0.1 }
  -- Only emit the capability for RPC version >= 5, since unit conversion for range capabilities is only supported in that case.
  if version.rpc >= 5 then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.temperatureSetpoint.temperatureSetpointRange({value = range, unit = unit}, { visibility = { displayed = false } }))
  end
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.temperatureSetpoint.temperatureSetpoint({value = temp, unit = unit}))
end

function common_utils.setpoint_limit_handler(device, ib, limit_field, device_type)
  local field = string.format("%s-%d", limit_field, ib.endpoint_id)
  local val = ib.data.value / 100.0

  local min_temp_in_c = default_min_and_max_temp_by_device_type[device_type].min_temp
  local max_temp_in_c = default_min_and_max_temp_by_device_type[device_type].max_temp
  if not min_temp_in_c or not max_temp_in_c or not common_utils.supports_temperature_number_endpoint(device, ib.endpoint_id) then return end

  val = utils.clamp_value(val, min_temp_in_c, max_temp_in_c)
  device:set_field(field, val, { persist = true })
end

function common_utils.handle_temperature_setpoint(device, cmd, device_type)
  local value = cmd.args.setpoint
  local _, temp_setpoint = device:get_latest_state(
    cmd.component, capabilities.temperatureSetpoint.ID,
    capabilities.temperatureSetpoint.temperatureSetpoint.NAME,
    0, { value = 0, unit = "C" }
  )
  local ep = device:component_to_endpoint(cmd.component)
  local min = device:get_field(string.format("%s-%d", common_utils.setpoint_limit_device_field.MIN_TEMP, ep))
    or default_min_and_max_temp_by_device_type[device_type].min_temp
  local max = device:get_field(string.format("%s-%d", common_utils.setpoint_limit_device_field.MAX_TEMP, ep))
    or default_min_and_max_temp_by_device_type[device_type].max_temp
  if not min or not max or not common_utils.supports_temperature_number_endpoint(device, ep) then return end

  if value > default_min_and_max_temp_by_device_type[device_type].max_temp and version.rpc <= 5 then
    value = utils.f_to_c(value)
  end
  if value < min or value > max then
    device.log.warn(string.format("Invalid setpoint (%s) outside the min (%s) and the max (%s)", value, min, max))
    device:emit_event_for_endpoint(ep, capabilities.temperatureSetpoint.temperatureSetpoint(temp_setpoint))
    return
  end
  device:send(clusters.TemperatureControl.commands.SetTemperature(device, ep, utils.round(value * 100), nil))
end

return common_utils
