-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local MatterDriver = require "st.matter.driver"
local fields = require "switch_utils.fields"
local st_utils = require "st.utils"
local clusters = require "st.matter.clusters"
local capabilities = require "st.capabilities"
local log = require "log"
local version = require "version"

local utils = {}

function utils.tbl_contains(array, value)
  if value == nil then return false end
  for _, element in pairs(array or {}) do
    if element == value then
      return true
    end
  end
  return false
end

function utils.convert_huesat_st_to_matter(val)
  return st_utils.clamp_value(math.floor((val * 0xFE) / 100.0 + 0.5), fields.CURRENT_HUESAT_ATTR_MIN, fields.CURRENT_HUESAT_ATTR_MAX)
end

function utils.get_field_for_endpoint(device, field, endpoint)
  return device:get_field(string.format("%s_%d", field, endpoint))
end

function utils.set_field_for_endpoint(device, field, endpoint, value, additional_params)
  device:set_field(string.format("%s_%d", field, endpoint), value, additional_params)
end

function utils.mired_to_kelvin(value, minOrMax)
  if value == 0 then -- shouldn't happen, but has
    value = 1
    log.warn(string.format("Received a color temperature of 0 mireds. Using a color temperature of 1 mired to avoid divide by zero"))
  end
  -- We divide inside the rounding and multiply outside of it because we expect these
  -- bounds to be multiples of 100. For the maximum mired value (minimum K value),
  -- add 1 before converting and round up to nearest hundreds. For the minimum mired
  -- (maximum K value) value, subtract 1 before converting and round down to nearest
  -- hundreds. Note that 1 is added/subtracted from the mired value in order to avoid
  -- rounding errors from the conversion of Kelvin to mireds.
  local kelvin_step_size = 100
  local rounding_value = 0.5
  if minOrMax == fields.COLOR_TEMP_MIN then
    return st_utils.round(fields.MIRED_KELVIN_CONVERSION_CONSTANT / (kelvin_step_size * (value + 1)) + rounding_value) * kelvin_step_size
  elseif minOrMax == fields.COLOR_TEMP_MAX then
    return st_utils.round(fields.MIRED_KELVIN_CONVERSION_CONSTANT / (kelvin_step_size * (value - 1)) - rounding_value) * kelvin_step_size
  else
    log.warn_with({hub_logs = true}, "Attempted to convert temperature unit for an undefined value")
  end
end

function utils.get_product_override_field(device, override_key)
  if fields.vendor_overrides[device.manufacturer_info.vendor_id]
  and fields.vendor_overrides[device.manufacturer_info.vendor_id][device.manufacturer_info.product_id]
  then
    return fields.vendor_overrides[device.manufacturer_info.vendor_id][device.manufacturer_info.product_id][override_key]
  end
end

function utils.check_field_name_updates(device)
  for _, field in ipairs(fields.updated_fields) do
    if device:get_field(field.current_field_name) then
      if field.updated_field_name ~= nil then
        device:set_field(field.updated_field_name, device:get_field(field.current_field_name), {persist = true})
      end
      device:set_field(field.current_field_name, nil)
    end
  end
end

function utils.check_switch_category_vendor_overrides(device)
  for _, product_id in ipairs(fields.switch_category_vendor_overrides[device.manufacturer_info.vendor_id] or {}) do
    if device.manufacturer_info.product_id == product_id then
      return true
    end
  end
end

--- device_type_supports_button_switch_combination helper function used to check
--- whether the device type for an endpoint is currently supported by a profile for
--- combination button/switch devices.
function utils.device_type_supports_button_switch_combination(device, endpoint_id)
  if utils.get_product_override_field(device, "ignore_combo_switch_button") then
    return false
  end
  local dimmable_eps = utils.get_endpoints_by_device_type(device, fields.DEVICE_TYPE_ID.LIGHT.DIMMABLE)
  return utils.tbl_contains(dimmable_eps, endpoint_id)
end

-- Some devices report multiple device types which are a subset of
-- a superset device type (Ex. Dimmable Light is a superset of On/Off Light).
-- We should map to the largest superset device type supported.
-- This can be done by matching to the device type with the highest ID
function utils.find_max_subset_device_type(ep, device_type_set)
  if ep.endpoint_id == 0 then return end -- EP-scoped device types not permitted on Root Node
  local primary_dt_id = ep.device_types[1] and ep.device_types[1].device_type_id
  if utils.tbl_contains(device_type_set, primary_dt_id) then
    for _, dt in ipairs(ep.device_types) do
      -- only device types in the subset should be considered.
      if utils.tbl_contains(device_type_set, dt.device_type_id) then
        primary_dt_id = math.max(primary_dt_id, dt.device_type_id)
      end
    end
    return primary_dt_id
  end
  return nil
end

--- find_default_endpoint is a helper function to handle situations where
--- device does not have endpoint ids in sequential order from 1
function utils.find_default_endpoint(device)
  -- Buttons should not be set on the main component for the Aqara Climate Sensor W100,
  if utils.get_product_override_field(device, "is_climate_sensor_w100") then
    return device.MATTER_DEFAULT_ENDPOINT
  end

  local switch_eps = device:get_endpoints(clusters.OnOff.ID)
  local button_eps = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH})

  local get_first_non_zero_endpoint = function(endpoints)
    table.sort(endpoints)
    for _,ep in ipairs(endpoints) do
      if ep ~= 0 then -- 0 is the matter RootNode endpoint
        return ep
      end
    end
    return nil
  end

  -- Return the first switch endpoint as the default endpoint if no button endpoints are present
  if #button_eps == 0 and #switch_eps > 0 then
    return get_first_non_zero_endpoint(switch_eps)
  end

  -- Return the first button endpoint as the default endpoint if no switch endpoints are present
  if #switch_eps == 0 and #button_eps > 0 then
    return get_first_non_zero_endpoint(button_eps)
  end

  -- If both switch and button endpoints are present, check the device type on the main switch
  -- endpoint. If it is not a supported device type, return the first button endpoint as the
  -- default endpoint.
  if #switch_eps > 0 and #button_eps > 0 then
    local default_endpoint_id = get_first_non_zero_endpoint(switch_eps)
    if utils.device_type_supports_button_switch_combination(device, default_endpoint_id) then
      return default_endpoint_id
    else
      device.log.warn("The main switch endpoint does not contain a supported device type for a component configuration with buttons")
      return get_first_non_zero_endpoint(button_eps)
    end
  end

  device.log.warn(string.format("Did not find default endpoint, will use endpoint %d instead", device.MATTER_DEFAULT_ENDPOINT))
  return device.MATTER_DEFAULT_ENDPOINT
end

function utils.component_to_endpoint(device, component)
  local map = device:get_field(fields.COMPONENT_TO_ENDPOINT_MAP) or {}
  if map[component] then
    return map[component]
  end
  return utils.find_default_endpoint(device)
end

--- An extension of the library function endpoint_to_component, used to support a mapping scheme
--- that optionally includes cluster and attribute ids so that multiple components can be mapped
--- to a single endpoint.
---
--- @param device any a Matter device object
--- @param opts number|table either an ep_id or a table { endpoint_id, optional(cluster_id), optional(attribute_id) }
--- where cluster_id is required for an attribute_id to be handled.
--- @return string component
function utils.endpoint_to_component(device, opts)
  if type(opts) == "number" then
    opts = { endpoint_id = opts }
  end
  for component, map_info in pairs(device:get_field(fields.COMPONENT_TO_ENDPOINT_MAP) or {}) do
    if type(map_info) == "number" and map_info == opts.endpoint_id then
      return component
    elseif type(map_info) == "table" and map_info.endpoint_id == opts.endpoint_id
      and (not map_info.cluster_id or (map_info.cluster_id == opts.cluster_id
      and (not map_info.attribute_ids or utils.tbl_contains(map_info.attribute_ids, opts.attribute_id)))) then
        return component
    end
  end
  return "main"
end

--- An extension of the library function emit_event_for_endpoint, used to support devices with
--- multiple components mapped to the same endpoint. This is handled by extending the parameters to optionally
--- include a cluster id and attribute id for more specific routing
---
--- @param device any a Matter device object
--- @param ep_info number|table endpoint_id or an ib (the ib data includes endpoint_id, cluster_id, and attribute_id fields)
--- @param event any a capability event object
function utils.emit_event_for_endpoint(device, ep_info, event)
  if type(ep_info) == "number" then
    ep_info = { endpoint_id = ep_info }
  end
  if device:get_field(fields.IS_PARENT_CHILD_DEVICE) then
    local child = utils.find_child(device, ep_info.endpoint_id)
    if child ~= nil then
      child:emit_event(event)
      return
    end
  end
  local comp_id = utils.endpoint_to_component(device, ep_info)
  local comp = device.profile.components[comp_id]
  device:emit_component_event(comp, event)
end

function utils.find_child(parent, ep_id)
  return parent:get_child_by_parent_assigned_key(string.format("%d", ep_id))
end

function utils.get_endpoint_info(device, endpoint_id)
  for _, ep in ipairs(device.endpoints) do
    if ep.endpoint_id == endpoint_id then return ep end
  end
  return {}
end

function utils.ep_supports_cluster(ep_info, cluster_id, opts)
  opts = opts or {}
  local clus_has_features = function(cluster, checked_feature)
    return (cluster.feature_map & checked_feature) == checked_feature
  end
  for _, cluster in ipairs(ep_info.clusters) do
    if ((cluster.cluster_id == cluster_id)
      and (opts.feature_bitmap == nil or clus_has_features(cluster, opts.feature_bitmap))
      and ((opts.cluster_type == nil and cluster.cluster_type == "SERVER" or cluster.cluster_type == "BOTH")
      or (opts.cluster_type == cluster.cluster_type))
      or (cluster_id == nil)) then
        return true
    end
  end
end

-- Fallback handler for responses that dont have their own handler
function utils.matter_handler(driver, device, response_block)
  device.log.info(string.format("Fallback handler for %s", response_block))
end

-- get a list of endpoints for a specified device type.
function utils.get_endpoints_by_device_type(device, device_type_id)
  local dt_eps = {}
  for _, ep in ipairs(device.endpoints) do
    for _, dt in ipairs(ep.device_types) do
      if dt.device_type_id == device_type_id then
        table.insert(dt_eps, ep.endpoint_id)
      end
    end
  end
  return dt_eps
end

--helper function to create list of multi press values
function utils.create_multi_press_values_list(size, supportsHeld)
  local list = {"pushed", "double"}
  if supportsHeld then table.insert(list, "held") end
  -- add multi press values of 3 or greater to the list
  for i=3, size do
    table.insert(list, string.format("pushed_%dx", i))
  end
  return list
end

function utils.detect_bridge(device)
  return #utils.get_endpoints_by_device_type(device, fields.DEVICE_TYPE_ID.AGGREGATOR) > 0
end

function utils.detect_matter_thing(device)
  for _, capability in ipairs(fields.supported_capabilities) do
    if device:supports_capability(capability) then
      return false
    end
  end
  return device:supports_capability(capabilities.refresh)
end

function utils.report_power_consumption_to_st_energy(device, latest_total_imported_energy_wh)
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

  local epoch_to_iso8601 = function(time) return os.date("!%Y-%m-%dT%H:%M:%SZ", time) end -- Return an ISO-8061 timestamp from UTC

  -- Report the energy consumed during the time interval. The unit of these values should be 'Wh'
  if not device:get_field(fields.ENERGY_MANAGEMENT_ENDPOINT) then
    device:emit_event(capabilities.powerConsumptionReport.powerConsumption({
      start = epoch_to_iso8601(last_time),
      ["end"] = epoch_to_iso8601(current_time - 1),
      deltaEnergy = energy_delta_wh,
      energy = latest_total_imported_energy_wh
    }))
  else
    device:emit_event_for_endpoint(device:get_field(fields.ENERGY_MANAGEMENT_ENDPOINT),capabilities.powerConsumptionReport.powerConsumption({
      start = epoch_to_iso8601(last_time),
      ["end"] = epoch_to_iso8601(current_time - 1),
      deltaEnergy = energy_delta_wh,
      energy = latest_total_imported_energy_wh
    }))
  end
end

function utils.lazy_load(sub_driver_name)
  if version.api >= 16 then
    return MatterDriver.lazy_load_sub_driver_v2(sub_driver_name)
  end
end

return utils
