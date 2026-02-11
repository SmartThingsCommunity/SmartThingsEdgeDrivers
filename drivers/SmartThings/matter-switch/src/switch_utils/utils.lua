-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local MatterDriver = require "st.matter.driver"
local fields = require "switch_utils.fields"
local st_utils = require "st.utils"
local version = require "version"
local clusters = require "st.matter.clusters"
local capabilities = require "st.capabilities"
local im = require "st.matter.interaction_model"
local log = require "log"

-- Include driver-side definitions when lua libs api version is < 11
if version.api < 11 then
  clusters.ElectricalEnergyMeasurement = require "embedded_clusters.ElectricalEnergyMeasurement"
  clusters.ElectricalPowerMeasurement = require "embedded_clusters.ElectricalPowerMeasurement"
  clusters.PowerTopology = require "embedded_clusters.PowerTopology"
end

if version.api < 16 then
  clusters.Descriptor = require "embedded_clusters.Descriptor"
end

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

function utils.remove_field_index(device, field_name, index)
  local new_table = device:get_field(field_name)
  if type(new_table) == "table" then
    new_table[index] = nil -- remove value associated with index from table
    device:set_field(field_name, new_table)
  end
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
  if device.manufacturer_info
  and fields.vendor_overrides[device.manufacturer_info.vendor_id]
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

--- Some devices report multiple device types which are a subset of a superset
--- device type (Ex. Dimmable Light is a superset of On/Off Light). We should map
--- to the largest superset device type supported.
--- This can be done by matching to the device type with the highest ID
--- note: that superset device types have a higher ID than those of their subset
--- is heuristic and could therefore break in the future, were the spec expanded
function utils.find_max_subset_device_type(ep, device_type_set)
  if ep.endpoint_id == 0 then return end -- EP-scoped device types not permitted on Root Node
  local primary_dt_id = -1
  for _, dt in ipairs(ep.device_types) do
    -- only device types in the subset should be considered.
    if utils.tbl_contains(device_type_set, dt.device_type_id) then
      primary_dt_id = math.max(primary_dt_id, dt.device_type_id)
    end
  end
  return (primary_dt_id > 0) and primary_dt_id or nil
end

--- Lights and Switches are Device Types that have Superset-style functionality
--- For all other device types, this function should be used to identify the primary device type
function utils.find_primary_device_type(ep_info)
  for _, dt in ipairs(ep_info.device_types) do
    if dt.device_type_id ~= fields.DEVICE_TYPE_ID.BRIDGED_NODE then
      -- if this is not a bridged node, return the first device type seen
      return dt.device_type_id
    end
  end
end

--- find_default_endpoint is a helper function to handle situations where
--- device does not have endpoint ids in sequential order from 1
function utils.find_default_endpoint(device)
  -- Buttons should not be set on the main component for the Aqara Climate Sensor W100,
  if utils.get_product_override_field(device, "is_climate_sensor_w100") then
    return device.MATTER_DEFAULT_ENDPOINT
  end

  local onoff_ep_ids = device:get_endpoints(clusters.OnOff.ID)
  local momentary_switch_ep_ids = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH})
  local fan_ep_ids = utils.get_endpoints_by_device_type(device, fields.DEVICE_TYPE_ID.FAN)
  local window_covering_ep_ids = utils.get_endpoints_by_device_type(device, fields.DEVICE_TYPE_ID.WINDOW_COVERING)

  local get_first_non_zero_endpoint = function(endpoints)
    table.sort(endpoints)
    for _,ep in ipairs(endpoints) do
      if ep ~= 0 then -- 0 is the matter RootNode endpoint
        return ep
      end
    end
    return nil
  end

  -- Return the first fan endpoint as the default endpoint if any is found
  if #fan_ep_ids > 0 then
    return get_first_non_zero_endpoint(fan_ep_ids)
  end

  -- Return the first onoff endpoint as the default endpoint if no momentary switch endpoints are present
  if #momentary_switch_ep_ids == 0 and #onoff_ep_ids > 0 then
    return get_first_non_zero_endpoint(onoff_ep_ids)
  end

  -- Return the first momentary switch endpoint as the default endpoint if no onoff endpoints are present
  if #onoff_ep_ids == 0 and #momentary_switch_ep_ids > 0 then
    return get_first_non_zero_endpoint(momentary_switch_ep_ids)
  end

  -- If both onoff and momentary switch endpoints are present, check the device type on the first onoff
  -- endpoint. If it is not a supported device type, return the first momentary switch endpoint as the
  -- default endpoint.
  if #onoff_ep_ids > 0 and #momentary_switch_ep_ids > 0 then
    local default_endpoint_id = get_first_non_zero_endpoint(onoff_ep_ids)
    if utils.device_type_supports_button_switch_combination(device, default_endpoint_id) then
      return default_endpoint_id
    else
      device.log.warn("The main switch endpoint does not contain a supported device type for a component configuration with buttons")
      return get_first_non_zero_endpoint(momentary_switch_ep_ids)
    end
  end

  -- Return the first window covering endpoint as the default endpoint if any is found
  if #window_covering_ep_ids > 0 then
    return get_first_non_zero_endpoint(window_covering_ep_ids)
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
--- to a single endpoint. This extension also handles the case that multiple endpoints map to the
--- same component
---
--- @param device any a Matter device object
--- @param ep_info number|table either an ep_id or a table { endpoint_id, optional(cluster_id), optional(attribute_id) }
--- where cluster_id is required for an attribute_id to be handled.
--- @return string component
function utils.endpoint_to_component(device, ep_info)
  if type(ep_info) == "number" then
    ep_info = { endpoint_id = ep_info }
  end
  for component, map_info in pairs(device:get_field(fields.COMPONENT_TO_ENDPOINT_MAP) or {}) do
    if type(map_info) == "number" and map_info == ep_info.endpoint_id then
      return component
    elseif type(map_info) == "table" then
      if type(map_info.endpoint_id) == "number" then
        map_info = {map_info}
      end
      for _, ep_map_info in ipairs(map_info) do
        if type(ep_map_info) == "number" and ep_map_info == ep_info.endpoint_id then
          return component
        elseif type(ep_map_info) == "table" and ep_map_info.endpoint_id == ep_info.endpoint_id
          and (not ep_map_info.cluster_id or (ep_map_info.cluster_id == ep_info.cluster_id
          and (not ep_map_info.attribute_ids or utils.tbl_contains(ep_map_info.attribute_ids, ep_info.attribute_id)))) then
            return component
        end
      end
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

function utils.find_child(parent_device, ep_id)
  local assigned_key = utils.get_field_for_endpoint(parent_device, fields.ASSIGNED_CHILD_KEY, ep_id) or ep_id
  return parent_device:get_child_by_parent_assigned_key(string.format("%d", assigned_key))
end

function utils.get_endpoint_info(device, endpoint_id)
  for _, ep in ipairs(device.endpoints) do
    if ep.endpoint_id == endpoint_id then return ep end
  end
  return {}
end

function utils.find_cluster_on_ep(ep, cluster_id, opts)
  opts = opts or {}
  local clus_has_features = function(cluster, checked_feature)
    return (cluster.feature_map & checked_feature) == checked_feature
  end
  for _, cluster in ipairs(ep.clusters) do
    if ((cluster.cluster_id == cluster_id)
      and (opts.feature_bitmap == nil or clus_has_features(cluster, opts.feature_bitmap))
      and ((opts.cluster_type == nil and cluster.cluster_type == "SERVER" or cluster.cluster_type == "BOTH")
      or (opts.cluster_type == cluster.cluster_type))
      or (cluster_id == nil)) then
        return cluster
    end
  end
end

-- Fallback handler for responses that dont have their own handler
function utils.matter_handler(driver, device, response_block)
  device.log.info(string.format("Fallback handler for %s", response_block))
end

-- get a list of endpoints for a specified device type.
function utils.get_endpoints_by_device_type(device, device_type_id, opts)
  opts = opts or {}
  local dt_eps = {}
  for _, ep in ipairs(device.endpoints) do
    for _, dt in ipairs(ep.device_types) do
      if dt.device_type_id == device_type_id then
        if opts.with_info then
          table.insert(dt_eps, ep)
        else
          table.insert(dt_eps, ep.endpoint_id)
        end
        break
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

--- Generalizes the 'get_latest_state' function to be callable with extra endpoint information, described below,
--- without directly specifying the expected component. See the 'get_latest_state' definition for more
--- information about parameters and expected functionality otherwise.
---
--- @param endpoint_info number|table an endpoint id or an ib (the ib data includes endpoint_id, cluster_id, and attribute_id fields)
function utils.get_latest_state_for_endpoint(device, endpoint_info, capability_id, attribute_id, default_value, default_state_table)
  if type(endpoint_info) == "number" then
    endpoint_info = { endpoint_id = endpoint_info }
  end

  local component = device:endpoint_to_component(endpoint_info)
  local state_device = utils.find_child(device, endpoint_info.endpoint_id) or device
  return state_device:get_latest_state(component, capability_id, attribute_id, default_value, default_state_table)
end

function utils.report_power_consumption_to_st_energy(device, endpoint_id, total_imported_energy_wh)
  local current_time = os.time()
  local last_time = device:get_field(fields.LAST_IMPORTED_REPORT_TIMESTAMP) or 0

  -- Ensure that the previous report was sent at least 15 minutes ago
  if fields.MINIMUM_ST_ENERGY_REPORT_INTERVAL >= (current_time - last_time) then
    return
  end
  device:set_field(fields.LAST_IMPORTED_REPORT_TIMESTAMP, current_time, { persist = true })

  local previous_imported_report = utils.get_latest_state_for_endpoint(device, endpoint_id, capabilities.powerConsumptionReport.ID,
    capabilities.powerConsumptionReport.powerConsumption.NAME, { energy = total_imported_energy_wh }) -- default value if nil
  -- Report the energy consumed during the time interval. The unit of these values should be 'Wh'
  local epoch_to_iso8601 = function(time) return os.date("!%Y-%m-%dT%H:%M:%SZ", time) end -- Return an ISO-8061 timestamp from UTC
  device:emit_event_for_endpoint(endpoint_id, capabilities.powerConsumptionReport.powerConsumption({
    start = epoch_to_iso8601(last_time),
    ["end"] = epoch_to_iso8601(current_time - 1),
    deltaEnergy = total_imported_energy_wh - previous_imported_report.energy,
    energy = total_imported_energy_wh
  }))
end

--- sets fields for handling EPs with the Electrical Sensor device type
---
--- @param device table a Matter device object
--- @param electrical_sensor_ep table an EP object that includes an Electrical Sensor device type
--- @param associated_endpoint_ids table EP IDs that are associated with the Electrical Sensor EP
--- @return boolean
function utils.set_fields_for_electrical_sensor_endpoint(device, electrical_sensor_ep, associated_endpoint_ids)
  if #associated_endpoint_ids == 0 then
    return false
  else
    local tags = ""
    if utils.find_cluster_on_ep(electrical_sensor_ep, clusters.ElectricalPowerMeasurement.ID) then tags = tags.."-power" end
    if utils.find_cluster_on_ep(electrical_sensor_ep, clusters.ElectricalEnergyMeasurement.ID) then tags = tags.."-energy-powerConsumption" end
    -- note: using the lowest valued EP ID here is arbitrary (not spec defined) and is done to create internal consistency
    -- Ex. for the NODE topology, electrical capabilities will then be associated with the default (aka lowest ID'd) OnOff EP
    table.sort(associated_endpoint_ids)
    local primary_associated_ep_id = associated_endpoint_ids[1]
    -- map the required electrical tags for this electrical sensor EP with the first associated EP ID, used later during profling.
    utils.set_field_for_endpoint(device, fields.ELECTRICAL_TAGS, primary_associated_ep_id, tags)
    utils.set_field_for_endpoint(device, fields.ASSIGNED_CHILD_KEY, electrical_sensor_ep.endpoint_id, string.format("%d", primary_associated_ep_id), { persist = true })
    return true
  end
end

function utils.handle_electrical_sensor_info(device)
  local electrical_sensor_eps = utils.get_endpoints_by_device_type(device, fields.DEVICE_TYPE_ID.ELECTRICAL_SENSOR, { with_info = true })
  if #electrical_sensor_eps == 0 then
    -- no Electrical Sensor EPs are supported. Set profiling data to false and return
    device:set_field(fields.profiling_data.POWER_TOPOLOGY, false, {persist=true})
    return
  end

  -- check the feature map for the first (or only) Electrical Sensor EP
  local endpoint_power_topology_cluster = utils.find_cluster_on_ep(electrical_sensor_eps[1], clusters.PowerTopology.ID) or {}
  local endpoint_power_topology_feature_map = endpoint_power_topology_cluster.feature_map or 0
  if clusters.PowerTopology.are_features_supported(clusters.PowerTopology.types.Feature.SET_TOPOLOGY, endpoint_power_topology_feature_map) then
    device:set_field(fields.ELECTRICAL_SENSOR_EPS, electrical_sensor_eps) -- assume any other stored EPs also have a SET topology
    local available_eps_req = im.InteractionRequest(im.InteractionRequest.RequestType.READ, {}) -- SET read
    for _, ep in ipairs(electrical_sensor_eps) do
      available_eps_req:merge(clusters.PowerTopology.attributes.AvailableEndpoints:read(device, ep.endpoint_id))
    end
    device:send(available_eps_req)
    return
  elseif clusters.PowerTopology.are_features_supported(clusters.PowerTopology.types.Feature.TREE_TOPOLOGY, endpoint_power_topology_feature_map) then
    device:set_field(fields.ELECTRICAL_SENSOR_EPS, electrical_sensor_eps) -- assume any other stored EPs also have a TREE topology
    local parts_list_req = im.InteractionRequest(im.InteractionRequest.RequestType.READ, {}) -- TREE read
    for _, ep in ipairs(electrical_sensor_eps) do
      parts_list_req:merge(clusters.Descriptor.attributes.PartsList:read(device, ep.endpoint_id))
    end
    device:send(parts_list_req)
    return
  elseif clusters.PowerTopology.are_features_supported(clusters.PowerTopology.types.Feature.NODE_TOPOLOGY, endpoint_power_topology_feature_map) then
    -- EP has a NODE topology, so there is only ONE Electrical Sensor EP
    device:set_field(fields.profiling_data.POWER_TOPOLOGY, clusters.PowerTopology.types.Feature.NODE_TOPOLOGY, {persist=true})
    if utils.set_fields_for_electrical_sensor_endpoint(device, electrical_sensor_eps[1], device:get_endpoints(clusters.OnOff.ID)) == false then
      device.log.warn("Electrical Sensor EP with NODE topology found, but no OnOff EPs exist. Electrical Sensor capabilities will not be exposed.")
    end
    return
  end
end

function utils.lazy_load(sub_driver_name)
  if version.api >= 16 then
    return MatterDriver.lazy_load_sub_driver_v2(sub_driver_name)
  end
end

function utils.lazy_load_if_possible(sub_driver_name)
  if version.api >= 16 then
    return MatterDriver.lazy_load_sub_driver_v2(sub_driver_name)
  elseif version.api >= 9 then
    return MatterDriver.lazy_load_sub_driver(require(sub_driver_name))
  else
    return require(sub_driver_name)
  end
end

--- helper for the switch subscribe override, which adds to a subscribed request for a checked device
---
--- @param checked_device any a Matter device object, either a parent or child device, so not necessarily the same as device
--- @param subscribe_request table a subscribe request that will be appended to as needed for the device
--- @param capabilities_seen table a list of capabilities that have already been checked by previously handled devices
--- @param attributes_seen table a list of attributes that have already been checked
--- @param events_seen table a list of events that have already been checked
--- @param subscribed_attributes table key-value pairs mapping capability ids to subscribed attributes
--- @param subscribed_events table key-value pairs mapping capability ids to subscribed events
function utils.populate_subscribe_request_for_device(checked_device, subscribe_request, capabilities_seen, attributes_seen, events_seen, subscribed_attributes, subscribed_events)
 for _, component in pairs(checked_device.st_store.profile.components) do
    for _, capability in pairs(component.capabilities) do
      if not capabilities_seen[capability.id] then
        for _, attr in ipairs(subscribed_attributes[capability.id] or {}) do
          local cluster_id = attr.cluster or attr._cluster.ID
          local attr_id = attr.ID or attr.attribute
          if not attributes_seen[cluster_id] or not attributes_seen[cluster_id][attr_id] then
            local ib = im.InteractionInfoBlock(nil, cluster_id, attr_id)
            subscribe_request:with_info_block(ib)
            attributes_seen[cluster_id] = attributes_seen[cluster_id] or {}
            attributes_seen[cluster_id][attr_id] = ib
          end
        end
        for _, event in ipairs(subscribed_events[capability.id] or {}) do
          local cluster_id = event.cluster or event._cluster.ID
          local event_id = event.ID or event.event
          if not events_seen[cluster_id] or not events_seen[cluster_id][event_id] then
            local ib = im.InteractionInfoBlock(nil, cluster_id, nil, event_id)
            subscribe_request:with_info_block(ib)
            events_seen[cluster_id] = events_seen[cluster_id] or {}
            events_seen[cluster_id][event_id] = ib
          end
        end
        capabilities_seen[capability.id] = true -- only loop through any capability once
      end
    end
  end
end

--- create and send a subscription request by checking all devices, accounting for both parent and child devices
---
--- @param device any a Matter device object
function utils.subscribe(device)
  local subscribe_request = im.InteractionRequest(im.InteractionRequest.RequestType.SUBSCRIBE, {})
  local devices_seen, capabilities_seen, attributes_seen, events_seen = {}, {}, {}, {}

  for _, endpoint_info in ipairs(device.endpoints) do
    local checked_device = utils.find_child(device, endpoint_info.endpoint_id) or device
    if not devices_seen[checked_device.id] then
      utils.populate_subscribe_request_for_device(checked_device, subscribe_request, capabilities_seen, attributes_seen, events_seen,
        device.driver.subscribed_attributes, device.driver.subscribed_events
      )
      devices_seen[checked_device.id] = true -- only loop through any device once
    end
  end
  -- The refresh capability command handler in the lua libs uses this key to determine which attributes to read. Note
  -- that only attributes_seen needs to be saved here, and not events_seen, since the refresh handler only checks
  -- attributes and not events.
  device:set_field(fields.SUBSCRIBED_ATTRIBUTES_KEY, attributes_seen)

  -- If the type of battery support has not yet been determined, add the PowerSource AttributeList to the list of
  -- subscribed attributes in order to determine which if any battery capability should be used.
  if device:get_field(fields.profiling_data.BATTERY_SUPPORT) == nil then
    local ib = im.InteractionInfoBlock(nil, clusters.PowerSource.ID, clusters.PowerSource.attributes.AttributeList.ID)
    subscribe_request:with_info_block(ib)
  end

  if #subscribe_request.info_blocks > 0 then
    device:send(subscribe_request)
  end
end

return utils
