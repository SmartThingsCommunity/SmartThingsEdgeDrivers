-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local version = require "version"
local im = require "st.matter.interaction_model"
local st_utils = require "st.utils"
local fields = require "switch_utils.fields"
local switch_utils = require "switch_utils.utils"
local color_utils = require "switch_utils.color_utils"
local cfg = require "switch_utils.device_configuration"
local device_cfg = cfg.DeviceCfg

-- Include driver-side definitions when lua libs api version is < 11
if version.api < 11 then
  clusters.ElectricalEnergyMeasurement = require "embedded_clusters.ElectricalEnergyMeasurement"
  clusters.PowerTopology = require "embedded_clusters.PowerTopology"
end

local AttributeHandlers = {}

-- [[ ON OFF CLUSTER ATTRIBUTES ]] --

function AttributeHandlers.on_off_attr_handler(driver, device, ib, response)
  if ib.data.value then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switch.switch.on())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switch.switch.off())
  end
  if type(device.register_native_capability_attr_handler) == "function" then
    device:register_native_capability_attr_handler("switch", "switch")
  end
end


-- [[ LEVEL CONTROL CLUSTER ATTRIBUTES ]] --

function AttributeHandlers.level_control_current_level_handler(driver, device, ib, response)
  if ib.data.value ~= nil then
    local level = ib.data.value
    if level > 0 then
      level = math.max(1, st_utils.round(level / 254.0 * 100))
    end
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switchLevel.level(level))
    if type(device.register_native_capability_attr_handler) == "function" then
      device:register_native_capability_attr_handler("switchLevel", "level")
    end
  end
end

function AttributeHandlers.level_bounds_handler_factory(minOrMax)
  return function(driver, device, ib, response)
    if ib.data.value == nil then
      return
    end
    local lighting_endpoints = device:get_endpoints(clusters.LevelControl.ID, {feature_bitmap = clusters.LevelControl.FeatureMap.LIGHTING})
    local lighting_support = switch_utils.tbl_contains(lighting_endpoints, ib.endpoint_id)
    -- If the lighting feature is supported then we should check if the reported level is at least 1.
    if lighting_support and ib.data.value < fields.SWITCH_LEVEL_LIGHTING_MIN then
      device.log.warn_with({hub_logs = true}, string.format("Lighting device reported a switch level %d outside of supported capability range", ib.data.value))
      return
    end
    -- Convert level from given range of 0-254 to range of 0-100.
    local level = st_utils.round(ib.data.value / 254.0 * 100)
    -- If the device supports the lighting feature, the minimum capability level should be 1 so we do not send a 0 value for the level attribute
    if lighting_support and level == 0 then
      level = 1
    end
    switch_utils.set_field_for_endpoint(device, fields.LEVEL_BOUND_RECEIVED..minOrMax, ib.endpoint_id, level)
    local min = switch_utils.get_field_for_endpoint(device, fields.LEVEL_BOUND_RECEIVED..fields.LEVEL_MIN, ib.endpoint_id)
    local max = switch_utils.get_field_for_endpoint(device, fields.LEVEL_BOUND_RECEIVED..fields.LEVEL_MAX, ib.endpoint_id)
    if min ~= nil and max ~= nil then
      if min < max then
        device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switchLevel.levelRange({ value = {minimum = min, maximum = max} }))
      else
        device.log.warn_with({hub_logs = true}, string.format("Device reported a min level value %d that is not lower than the reported max level value %d", min, max))
      end
      switch_utils.set_field_for_endpoint(device, fields.LEVEL_BOUND_RECEIVED..fields.LEVEL_MAX, ib.endpoint_id, nil)
      switch_utils.set_field_for_endpoint(device, fields.LEVEL_BOUND_RECEIVED..fields.LEVEL_MIN, ib.endpoint_id, nil)
    end
  end
end


-- [[ COLOR CONTROL CLUSTER ATTRIBUTES ]] --

function AttributeHandlers.current_hue_handler(driver, device, ib, response)
  if device:get_field(fields.COLOR_MODE) ~= fields.X_Y_COLOR_MODE and ib.data.value ~= nil then
    local hue = math.floor((ib.data.value / 0xFE * 100) + 0.5)
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.colorControl.hue(hue))
  end
  if type(device.register_native_capability_attr_handler) == "function" then
    device:register_native_capability_attr_handler("colorControl", "hue")
  end
end

function AttributeHandlers.current_saturation_handler(driver, device, ib, response)
  if device:get_field(fields.COLOR_MODE) ~= fields.X_Y_COLOR_MODE and ib.data.value ~= nil then
    local sat = math.floor((ib.data.value / 0xFE * 100) + 0.5)
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.colorControl.saturation(sat))
  end
  if type(device.register_native_capability_attr_handler) == "function" then
    device:register_native_capability_attr_handler("colorControl", "saturation")
  end
end

function AttributeHandlers.color_temperature_mireds_handler(driver, device, ib, response)
  local temp_in_mired = ib.data.value
  if temp_in_mired == nil then
    return
  end
  if (temp_in_mired < fields.COLOR_TEMPERATURE_MIRED_MIN or temp_in_mired > fields.COLOR_TEMPERATURE_MIRED_MAX) then
    device.log.warn_with({hub_logs = true}, string.format("Device reported color temperature %d mired outside of sane range of %.2f-%.2f", temp_in_mired, fields.COLOR_TEMPERATURE_MIRED_MIN, fields.COLOR_TEMPERATURE_MIRED_MAX))
    return
  end
  local min_temp_mired = switch_utils.get_field_for_endpoint(device, fields.COLOR_TEMP_BOUND_RECEIVED_MIRED..fields.COLOR_TEMP_MIN, ib.endpoint_id)
  local max_temp_mired = switch_utils.get_field_for_endpoint(device, fields.COLOR_TEMP_BOUND_RECEIVED_MIRED..fields.COLOR_TEMP_MAX, ib.endpoint_id)

  local temp = st_utils.round(fields.MIRED_KELVIN_CONVERSION_CONSTANT/temp_in_mired)
  if min_temp_mired ~= nil and temp_in_mired <= min_temp_mired then
    temp = switch_utils.get_field_for_endpoint(device, fields.COLOR_TEMP_BOUND_RECEIVED_KELVIN..fields.COLOR_TEMP_MAX, ib.endpoint_id)
  elseif max_temp_mired ~= nil and temp_in_mired >= max_temp_mired then
    temp = switch_utils.get_field_for_endpoint(device, fields.COLOR_TEMP_BOUND_RECEIVED_KELVIN..fields.COLOR_TEMP_MIN, ib.endpoint_id)
  end

  local temp_device = device
  if device:get_field(fields.IS_PARENT_CHILD_DEVICE) == true then
    temp_device = switch_utils.find_child(device, ib.endpoint_id) or device
  end
  local most_recent_temp = temp_device:get_field(fields.MOST_RECENT_TEMP)
  -- this is to avoid rounding errors from the round-trip conversion of Kelvin to mireds
  if most_recent_temp ~= nil and
    most_recent_temp <= st_utils.round(fields.MIRED_KELVIN_CONVERSION_CONSTANT/(temp_in_mired - 1)) and
    most_recent_temp >= st_utils.round(fields.MIRED_KELVIN_CONVERSION_CONSTANT/(temp_in_mired + 1)) then
      temp = most_recent_temp
  end
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.colorTemperature.colorTemperature(temp))
end

function AttributeHandlers.current_x_handler(driver, device, ib, response)
  if device:get_field(fields.COLOR_MODE) == clusters.ColorControl.types.ColorMode.CURRENT_HUE_AND_CURRENT_SATURATION then
    return
  end
  local y = device:get_field(fields.RECEIVED_Y)
  --TODO it is likely that both x and y attributes are in the response (not guaranteed though)
  -- if they are we can avoid setting fields on the device.
  if y == nil then
    device:set_field(fields.RECEIVED_X, ib.data.value)
  else
    local x = ib.data.value
    local h, s, _ = color_utils.safe_xy_to_hsv(x, y, nil)
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.colorControl.hue(h))
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.colorControl.saturation(s))
    device:set_field(fields.RECEIVED_Y, nil)
  end
end

function AttributeHandlers.current_y_handler(driver, device, ib, response)
  if device:get_field(fields.COLOR_MODE) == clusters.ColorControl.types.ColorMode.CURRENT_HUE_AND_CURRENT_SATURATION then
    return
  end
  local x = device:get_field(fields.RECEIVED_X)
  if x == nil then
    device:set_field(fields.RECEIVED_Y, ib.data.value)
  else
    local y = ib.data.value
    local h, s, _ = color_utils.safe_xy_to_hsv(x, y, nil)
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.colorControl.hue(h))
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.colorControl.saturation(s))
    device:set_field(fields.RECEIVED_X, nil)
  end
end

function AttributeHandlers.color_mode_handler(driver, device, ib, response)
  if ib.data.value == device:get_field(fields.COLOR_MODE)
    or (ib.data.value ~= clusters.ColorControl.types.ColorMode.CURRENT_HUE_AND_CURRENT_SATURATION
    and ib.data.value ~= clusters.ColorControl.types.ColorMode.CURRENTX_AND_CURRENTY) then
      return
  end
  device:set_field(fields.COLOR_MODE, ib.data.value)
  local req = im.InteractionRequest(im.InteractionRequest.RequestType.READ, {})
  if ib.data.value == clusters.ColorControl.types.ColorMode.CURRENT_HUE_AND_CURRENT_SATURATION then
    req:merge(clusters.ColorControl.attributes.CurrentHue:read())
    req:merge(clusters.ColorControl.attributes.CurrentSaturation:read())
  elseif ib.data.value == clusters.ColorControl.types.ColorMode.CURRENTX_AND_CURRENTY then
    req:merge(clusters.ColorControl.attributes.CurrentX:read())
    req:merge(clusters.ColorControl.attributes.CurrentY:read())
  end
  if #req.info_blocks > 0 then
    device:send(req)
  end
end

--TODO setup configure handler to read this attribute.
function AttributeHandlers.color_capabilities_handler(driver, device, ib, response)
  if ib.data.value ~= nil then
    if ib.data.value & 0x1 then
      device:set_field(fields.HUESAT_SUPPORT, true)
    end
  end
end

function AttributeHandlers.color_temp_physical_mireds_bounds_factory(minOrMax)
  return function(driver, device, ib, response)
    local temp_in_mired = ib.data.value
    if temp_in_mired == nil then
      return
    end
    if (temp_in_mired < fields.COLOR_TEMPERATURE_MIRED_MIN or temp_in_mired > fields.COLOR_TEMPERATURE_MIRED_MAX) then
      device.log.warn_with({hub_logs = true}, string.format("Device reported a color temperature %d mired outside of sane range of %.2f-%.2f", temp_in_mired, fields.COLOR_TEMPERATURE_MIRED_MIN, fields.COLOR_TEMPERATURE_MIRED_MAX))
      return
    end
    local temp_in_kelvin = switch_utils.mired_to_kelvin(temp_in_mired, minOrMax)
    switch_utils.set_field_for_endpoint(device, fields.COLOR_TEMP_BOUND_RECEIVED_KELVIN..minOrMax, ib.endpoint_id, temp_in_kelvin)
    -- the minimum color temp in kelvin corresponds to the maximum temp in mireds
    if minOrMax == fields.COLOR_TEMP_MIN then
      switch_utils.set_field_for_endpoint(device, fields.COLOR_TEMP_BOUND_RECEIVED_MIRED..fields.COLOR_TEMP_MAX, ib.endpoint_id, temp_in_mired)
    else
      switch_utils.set_field_for_endpoint(device, fields.COLOR_TEMP_BOUND_RECEIVED_MIRED..fields.COLOR_TEMP_MIN, ib.endpoint_id, temp_in_mired)
    end
    local min = switch_utils.get_field_for_endpoint(device, fields.COLOR_TEMP_BOUND_RECEIVED_KELVIN..fields.COLOR_TEMP_MIN, ib.endpoint_id)
    local max = switch_utils.get_field_for_endpoint(device, fields.COLOR_TEMP_BOUND_RECEIVED_KELVIN..fields.COLOR_TEMP_MAX, ib.endpoint_id)
    if min ~= nil and max ~= nil then
      if min < max then
        device:emit_event_for_endpoint(ib.endpoint_id, capabilities.colorTemperature.colorTemperatureRange({ value = {minimum = min, maximum = max} }))
      else
        device.log.warn_with({hub_logs = true}, string.format("Device reported a min color temperature %d K that is not lower than the reported max color temperature %d K", min, max))
      end
    end
  end
end


-- [[ ELECTRICAL POWER MEASUREMENT CLUSTER ATTRIBUTES ]] --

function AttributeHandlers.active_power_handler(driver, device, ib, response)
  if ib.data.value then
    local watt_value = ib.data.value / 1000 -- convert received milliwatt to watt
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.powerMeter.power({ value = watt_value, unit = "W"}))
  end
  if type(device.register_native_capability_attr_handler) == "function" then
    device:register_native_capability_attr_handler("powerMeter","power")
  end
end


-- [[ VALVE CONFIGURATION AND CONTROL CLUSTER ATTRIBUTES ]] --

function AttributeHandlers.valve_configuration_current_state_handler(driver, device, ib, response)
  if ib.data.value == 0 then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.valve.valve.closed())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.valve.valve.open())
  end
end

function AttributeHandlers.valve_configuration_current_level_handler(driver, device, ib, response)
  if ib.data.value then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.level.level(ib.data.value))
  end
end


-- [[ ELECTRICAL ENERGY MEASUREMENT CLUSTER ATTRIBUTES ]] --

function AttributeHandlers.energy_imported_factory(is_periodic_report)
  return function(driver, device, ib, response)
    if version.api < 11 then
      clusters.ElectricalEnergyMeasurement.types.EnergyMeasurementStruct:augment_type(ib.data)
    end
    if ib.data.elements.energy then
      local energy_imported_wh = ib.data.elements.energy.value / 1000 -- convert received milliwatt-hour to watt-hour
      if is_periodic_report then
        -- handle this report only if cumulative reports are not supported
        if device:get_field(fields.CUMULATIVE_REPORTS_SUPPORTED) then return end
        local energy_meter_latest_state = switch_utils.get_latest_state_for_endpoint(
          device, ib, capabilities.energyMeter.ID, capabilities.energyMeter.energy.NAME
        ) or 0
        energy_imported_wh = energy_imported_wh + energy_meter_latest_state
      else
        -- the field containing the offset may be associated with a child device
        local field_device = switch_utils.find_child(device, ib.endpoint_id) or device
        local energy_meter_offset = field_device:get_field(fields.ENERGY_METER_OFFSET) or 0.0
        energy_imported_wh = energy_imported_wh - energy_meter_offset
      end
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.energyMeter.energy({ value = energy_imported_wh, unit = "Wh" }))
      switch_utils.report_power_consumption_to_st_energy(device, ib.endpoint_id, energy_imported_wh)
    else
      device.log.warn("Received data from the energy imported attribute does not include a numerical energy value")
    end
  end
end


-- [[ POWER TOPOLOGY CLUSTER ATTRIBUTES ]] --

--- AvailableEndpoints: This attribute SHALL indicate the list of endpoints capable of
--- providing power to and/or consuming power from the endpoint hosting this server.
---
--- In the case there are multiple endpoints supporting the PowerTopology cluster with
--- SET feature, all AvailableEndpoints responses must be handled before profiling.
function AttributeHandlers.available_endpoints_handler(driver, device, ib, response)
  local set_topology_eps = device:get_field(fields.ELECTRICAL_SENSOR_EPS)
  for i, set_ep_info in pairs(set_topology_eps or {}) do
    if ib.endpoint_id == set_ep_info.endpoint_id then
      -- since EP response is being handled here, remove it from the ELECTRICAL_SENSOR_EPS table
      switch_utils.remove_field_index(device, fields.ELECTRICAL_SENSOR_EPS, i)
      local available_endpoints_ids = {}
      for _, element in pairs(ib.data.elements or {}) do
        table.insert(available_endpoints_ids, element.value)
      end
      -- set the required profile elements ("-power", etc.) to one of these EP IDs for later profiling.
      -- set an assigned child key in the case this will emit events on an EDGE_CHILD device
      switch_utils.set_fields_for_electrical_sensor_endpoint(device, set_ep_info, available_endpoints_ids)
      break
    end
  end
  if #set_topology_eps == 0 then -- in other words, all AvailableEndpoints attribute responses have been handled
    device:set_field(fields.profiling_data.POWER_TOPOLOGY, clusters.PowerTopology.types.Feature.SET_TOPOLOGY, {persist=true})
    device_cfg.match_profile(driver, device)
  end
end


-- [[ DESCRIPTOR CLUSTER ATTRIBUTES ]] --

function AttributeHandlers.parts_list_handler(driver, device, ib, response)
  local tree_topology_eps = device:get_field(fields.ELECTRICAL_SENSOR_EPS)
  for i, tree_ep_info in pairs(tree_topology_eps or {}) do
    if ib.endpoint_id == tree_ep_info.endpoint_id then
      -- since EP response is being handled here, remove it from the ELECTRICAL_SENSOR_EPS table
      switch_utils.remove_field_index(device, fields.ELECTRICAL_SENSOR_EPS, i)
      local associated_endpoints_ids = {}
      for _, element in pairs(ib.data.elements or {}) do
        table.insert(associated_endpoints_ids, element.value)
      end
      -- set the required profile elements ("-power", etc.) to one of these EP IDs for later profiling.
      -- set an assigned child key in the case this will emit events on an EDGE_CHILD device
      switch_utils.set_fields_for_electrical_sensor_endpoint(device, tree_ep_info, associated_endpoints_ids)
      break
    end
  end
  if #tree_topology_eps == 0 then -- in other words, all PartsList attribute responses for TREE Electrical Sensor EPs have been handled
    device:set_field(fields.profiling_data.POWER_TOPOLOGY, clusters.PowerTopology.types.Feature.TREE_TOPOLOGY, {persist=true})
    device_cfg.match_profile(driver, device)
  end
end


-- [[ POWER SOURCE CLUSTER ATTRIBUTES ]] --

function AttributeHandlers.bat_percent_remaining_handler(driver, device, ib, response)
  if ib.data.value then
    device:emit_event(capabilities.battery.battery(math.floor(ib.data.value / 2.0 + 0.5)))
  end
end

function AttributeHandlers.bat_charge_level_handler(driver, device, ib, response)
  if ib.data.value == clusters.PowerSource.types.BatChargeLevelEnum.OK then
    device:emit_event(capabilities.batteryLevel.battery.normal())
  elseif ib.data.value == clusters.PowerSource.types.BatChargeLevelEnum.WARNING then
    device:emit_event(capabilities.batteryLevel.battery.warning())
  elseif ib.data.value == clusters.PowerSource.types.BatChargeLevelEnum.CRITICAL then
    device:emit_event(capabilities.batteryLevel.battery.critical())
  end
end

function AttributeHandlers.power_source_attribute_list_handler(driver, device, ib, response)
  local previous_battery_support = device:get_field(fields.profiling_data.BATTERY_SUPPORT)
  device:set_field(fields.profiling_data.BATTERY_SUPPORT, fields.battery_support.NO_BATTERY, {persist=true})
  for _, attr in ipairs(ib.data.elements or {}) do
    if attr.value == clusters.PowerSource.attributes.BatPercentRemaining.ID then
      device:set_field(fields.profiling_data.BATTERY_SUPPORT, fields.battery_support.BATTERY_PERCENTAGE, {persist=true})
      break
    elseif attr.value == clusters.PowerSource.attributes.BatChargeLevel.ID and
      device:get_field(fields.profiling_data.BATTERY_SUPPORT) ~= fields.battery_support.BATTERY_PERCENTAGE then -- don't overwrite if percentage support is already detected
      device:set_field(fields.profiling_data.BATTERY_SUPPORT, fields.battery_support.BATTERY_LEVEL, {persist=true})
    end
  end
  if not previous_battery_support or previous_battery_support ~= device:get_field(fields.profiling_data.BATTERY_SUPPORT) then
    device_cfg.match_profile(driver, device)
  end
end


-- [[ SWITCH CLUSTER ATTRIBUTES ]] --

function AttributeHandlers.multi_press_max_handler(driver, device, ib, response)
  local max = ib.data.value or 1 --get max number of presses
  device.log.debug("Device supports "..max.." presses")
  -- capability only supports up to 6 presses
  if max > 6 then
    device.log.info("Device supports more than 6 presses")
    max = 6
  end
  local MSL = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_LONG_PRESS})
  local supportsHeld = switch_utils.tbl_contains(MSL, ib.endpoint_id)
  local values = switch_utils.create_multi_press_values_list(max, supportsHeld)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.button.supportedButtonValues(values, {visibility = {displayed = false}}))
end


-- [[ FAN CONTROL CLUSTER ATTRIBUTES ]] --

function AttributeHandlers.fan_mode_handler(driver, device, ib, response)
  if ib.data.value == clusters.FanControl.attributes.FanMode.OFF then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.fanMode.fanMode("off"))
  elseif ib.data.value == clusters.FanControl.attributes.FanMode.LOW then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.fanMode.fanMode("low"))
  elseif ib.data.value == clusters.FanControl.attributes.FanMode.MEDIUM then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.fanMode.fanMode("medium"))
  elseif ib.data.value == clusters.FanControl.attributes.FanMode.HIGH then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.fanMode.fanMode("high"))
  else
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.fanMode.fanMode("auto"))
  end
end

function AttributeHandlers.fan_mode_sequence_handler(driver, device, ib, response)
  local supportedFanModes
  if ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_LOW_MED_HIGH then
    supportedFanModes = {
      capabilities.fanMode.fanMode.off.NAME,
      capabilities.fanMode.fanMode.low.NAME,
      capabilities.fanMode.fanMode.medium.NAME,
      capabilities.fanMode.fanMode.high.NAME
    }
  elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_LOW_HIGH then
    supportedFanModes = {
      capabilities.fanMode.fanMode.off.NAME,
      capabilities.fanMode.fanMode.low.NAME,
      capabilities.fanMode.fanMode.high.NAME
    }
  elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_LOW_MED_HIGH_AUTO then
    supportedFanModes = {
      capabilities.fanMode.fanMode.off.NAME,
      capabilities.fanMode.fanMode.low.NAME,
      capabilities.fanMode.fanMode.medium.NAME,
      capabilities.fanMode.fanMode.high.NAME,
      capabilities.fanMode.fanMode.auto.NAME
    }
  elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_LOW_HIGH_AUTO then
    supportedFanModes = {
      capabilities.fanMode.fanMode.off.NAME,
      capabilities.fanMode.fanMode.low.NAME,
      capabilities.fanMode.fanMode.high.NAME,
      capabilities.fanMode.fanMode.auto.NAME
    }
  elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_ON_AUTO then
    supportedFanModes = {
      capabilities.fanMode.fanMode.off.NAME,
      capabilities.fanMode.fanMode.high.NAME,
      capabilities.fanMode.fanMode.auto.NAME
    }
  else
    supportedFanModes = {
      capabilities.fanMode.fanMode.off.NAME,
      capabilities.fanMode.fanMode.high.NAME
    }
  end
  local event = capabilities.fanMode.supportedFanModes(supportedFanModes, {visibility = {displayed = false}})
  device:emit_event_for_endpoint(ib.endpoint_id, event)
end

function AttributeHandlers.percent_current_handler(driver, device, ib, response)
  if ib.data.value == nil or ib.data.value < 0 or ib.data.value > 100 then
    return
  end
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.fanSpeedPercent.percent(ib.data.value))
end

return AttributeHandlers
