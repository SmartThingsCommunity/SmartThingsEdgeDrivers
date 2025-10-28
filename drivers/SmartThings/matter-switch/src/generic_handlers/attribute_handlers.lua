-- Copyright 2025 SmartThings
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
local version = require "version"
local im = require "st.matter.interaction_model"

local st_utils = require "st.utils"
local fields = require "utils.switch_fields"
local switch_utils = require "utils.switch_utils"
local color_utils = require "utils.color_utils"

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
    local level = math.floor((ib.data.value / 254.0 * 100) + 0.5)
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
  if device:get_field(fields.COLOR_MODE) == fields.X_Y_COLOR_MODE  or ib.data.value == nil then
    return
  end
  local hue = math.floor((ib.data.value / 0xFE * 100) + 0.5)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.colorControl.hue(hue))
end

function AttributeHandlers.current_saturation_handler(driver, device, ib, response)
  if device:get_field(fields.COLOR_MODE) == fields.X_Y_COLOR_MODE  or ib.data.value == nil then
    return
  end
  local sat = math.floor((ib.data.value / 0xFE * 100) + 0.5)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.colorControl.saturation(sat))
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
  if device:get_field(fields.COLOR_MODE) == fields.HUE_SAT_COLOR_MODE then
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
  if device:get_field(fields.COLOR_MODE) == fields.HUE_SAT_COLOR_MODE then
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
  if ib.data.value == device:get_field(fields.COLOR_MODE) or (ib.data.value ~= fields.HUE_SAT_COLOR_MODE and ib.data.value ~= fields.X_Y_COLOR_MODE) then
    return
  end
  device:set_field(fields.COLOR_MODE, ib.data.value)
  local req = im.InteractionRequest(im.InteractionRequest.RequestType.READ, {})
  if ib.data.value == fields.HUE_SAT_COLOR_MODE then
    req:merge(clusters.ColorControl.attributes.CurrentHue:read())
    req:merge(clusters.ColorControl.attributes.CurrentSaturation:read())
  elseif ib.data.value == fields.X_Y_COLOR_MODE then
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


-- [[ ILLUMINANCE CLUSTER ATTRIBUTES ]] --

function AttributeHandlers.illuminance_measured_value_handler(driver, device, ib, response)
  local lux = math.floor(10 ^ ((ib.data.value - 1) / 10000))
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.illuminanceMeasurement.illuminance(lux))
end


-- [[ OCCUPANCY CLUSTER ATTRIBUTES ]] --

function AttributeHandlers.occupancy_handler(driver, device, ib, response)
  device:emit_event(ib.data.value == 0x01 and capabilities.motionSensor.motion.active() or capabilities.motionSensor.motion.inactive())
end


-- [[ ELECTRICAL POWER MEASUREMENT CLUSTER ATTRIBUTES ]] --

function AttributeHandlers.active_power_handler(driver, device, ib, response)
  if ib.data.value then
    local watt_value = ib.data.value / fields.CONVERSION_CONST_MILLIWATT_TO_WATT
    if ib.endpoint_id ~= 0 then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.powerMeter.power({ value = watt_value, unit = "W"}))
    else
      -- when energy management is defined in the root endpoint(0), replace it with the first switch endpoint and process it.
      device:emit_event_for_endpoint(device:get_field(fields.ENERGY_MANAGEMENT_ENDPOINT), capabilities.powerMeter.power({ value = watt_value, unit = "W"}))
    end
    if type(device.register_native_capability_attr_handler) == "function" then
      device:register_native_capability_attr_handler("powerMeter","power")
    end
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

function AttributeHandlers.cumul_energy_imported_handler(driver, device, ib, response)
  if ib.data.elements.energy then
    local watt_hour_value = ib.data.elements.energy.value / fields.CONVERSION_CONST_MILLIWATT_TO_WATT
    device:set_field(fields.TOTAL_IMPORTED_ENERGY, watt_hour_value, {persist = true})
    if ib.endpoint_id ~= 0 then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.energyMeter.energy({ value = watt_hour_value, unit = "Wh" }))
    else
      -- when energy management is defined in the root endpoint(0), replace it with the first switch endpoint and process it.
      device:emit_event_for_endpoint(device:get_field(fields.ENERGY_MANAGEMENT_ENDPOINT), capabilities.energyMeter.energy({ value = watt_hour_value, unit = "Wh" }))
    end
    switch_utils.report_power_consumption_to_st_energy(device, device:get_field(fields.TOTAL_IMPORTED_ENERGY))
  end
end

function AttributeHandlers.per_energy_imported_handler(driver, device, ib, response)
  if ib.data.elements.energy then
    local watt_hour_value = ib.data.elements.energy.value / fields.CONVERSION_CONST_MILLIWATT_TO_WATT
    local latest_energy_report = device:get_field(fields.TOTAL_IMPORTED_ENERGY) or 0
    local summed_energy_report = latest_energy_report + watt_hour_value
    device:set_field(fields.TOTAL_IMPORTED_ENERGY, summed_energy_report, {persist = true})
    device:emit_event(capabilities.energyMeter.energy({ value = summed_energy_report, unit = "Wh" }))
    switch_utils.report_power_consumption_to_st_energy(device, device:get_field(fields.TOTAL_IMPORTED_ENERGY))
  end
end

function AttributeHandlers.energy_imported_factory(is_cumulative_report)
  return function(driver, device, ib, response)
    -- workaround: ignore devices supporting Eve's private energy cluster AND the ElectricalEnergyMeasurement cluster
    local EVE_MANUFACTURER_ID, EVE_PRIVATE_CLUSTER_ID = 0x130A, 0x130AFC01
    local eve_private_energy_eps = device:get_endpoints(EVE_PRIVATE_CLUSTER_ID)
    if device.manufacturer_info.vendor_id == EVE_MANUFACTURER_ID and #eve_private_energy_eps > 0 then
      return
    end

    if is_cumulative_report then
      AttributeHandlers.cumul_energy_imported_handler(driver, device, ib, response)
    elseif device:get_field(fields.CUMULATIVE_REPORTS_NOT_SUPPORTED) then
      AttributeHandlers.per_energy_imported_handler(driver, device, ib, response)
    end
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
  local profile_name = ""

  local button_eps = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH})
  for _, attr in ipairs(ib.data.elements) do
    -- Re-profile the device if BatPercentRemaining (Attribute ID 0x0C) or
    -- BatChargeLevel (Attribute ID 0x0E) is present.
    if attr.value == 0x0C then
      profile_name = "button-battery"
      break
    elseif attr.value == 0x0E then
      profile_name = "button-batteryLevel"
      break
    end
  end
  if profile_name ~= "" then
    if #button_eps > 1 then
      profile_name = string.format("%d-", #button_eps) .. profile_name
    end

    if switch_utils.get_product_override_field(device, "is_climate_sensor_w100") then
      profile_name = profile_name .. "-temperature-humidity"
    end
    device:try_update_metadata({ profile = profile_name })
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


-- [[ TEMPERATURE MEASUREMENT CLUSTER ATTRIBUTES ]] --

function AttributeHandlers.temperature_measured_value_handler(driver, device, ib, response)
  local measured_value = ib.data.value
  if measured_value ~= nil then
    local temp = measured_value / 100.0
    local unit = "C"
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.temperatureMeasurement.temperature({value = temp, unit = unit}))
  end
end

function AttributeHandlers.temperature_measured_value_bounds_factory(minOrMax)
  return function(driver, device, ib, response)
    if ib.data.value == nil then
      return
    end
    local temp = ib.data.value / 100.0
    local unit = "C"
    switch_utils.set_field_for_endpoint(device, fields.TEMP_BOUND_RECEIVED..minOrMax, ib.endpoint_id, temp)
    local min = switch_utils.get_field_for_endpoint(device, fields.TEMP_BOUND_RECEIVED..fields.TEMP_MIN, ib.endpoint_id)
    local max = switch_utils.get_field_for_endpoint(device, fields.TEMP_BOUND_RECEIVED..fields.TEMP_MAX, ib.endpoint_id)
    if min ~= nil and max ~= nil then
      if min < max then
        -- Only emit the capability for RPC version >= 5 (unit conversion for
        -- temperature range capability is only supported for RPC >= 5)
        if version.rpc >= 5 then
          device:emit_event_for_endpoint(ib.endpoint_id, capabilities.temperatureMeasurement.temperatureRange({ value = { minimum = min, maximum = max }, unit = unit }))
        end
        switch_utils.set_field_for_endpoint(device, fields.TEMP_BOUND_RECEIVED..fields.TEMP_MIN, ib.endpoint_id, nil)
        switch_utils.set_field_for_endpoint(device, fields.TEMP_BOUND_RECEIVED..fields.TEMP_MAX, ib.endpoint_id, nil)
      else
        device.log.warn_with({hub_logs = true}, string.format("Device reported a min temperature %d that is not lower than the reported max temperature %d", min, max))
      end
    end
  end
end


-- [[ RELATIVE HUMIDITY MEASUREMENT CLUSTER ATTRIBUTES ]] --

function AttributeHandlers.relative_humidity_measured_value_handler(driver, device, ib, response)
  local measured_value = ib.data.value
  if measured_value ~= nil then
    local humidity = st_utils.round(measured_value / 100.0)
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.relativeHumidityMeasurement.humidity(humidity))
  end
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