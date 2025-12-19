-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local embedded_cluster_utils = require "sensor_utils.embedded_cluster_utils"
local sensor_utils = require "sensor_utils.utils"
local fields = require "sensor_utils.fields"

-- This can be removed once LuaLibs supports the SoilMeasurement cluster
if not pcall(function(cluster) return clusters[cluster] end,
             "SoilMeasurement") then
  clusters.SoilMeasurement = require "embedded_clusters.SoilMeasurement"
end

local SOIL_SENSOR_DEVICE_TYPE_ID = 0x0045

local soil_sensor_utils = {}

function soil_sensor_utils.is_matter_soil_sensor(opts, driver, device)
  for _, ep in ipairs(device.endpoints) do
    for _, dt in ipairs(ep.device_types) do
      if dt.device_type_id == SOIL_SENSOR_DEVICE_TYPE_ID then
        return true
      end
    end
  end
  return false
end

function soil_sensor_utils.match_profile(device, battery_supported)
  local temp_eps = embedded_cluster_utils.get_endpoints(device, clusters.TemperatureMeasurement.ID)
  
  local profile_name = "soil-sensor"
  
  if #temp_eps > 0 then
    profile_name = "soil-sensor-temperature"
  end
  
  if battery_supported == fields.battery_support.BATTERY_PERCENTAGE then
    profile_name = profile_name .. "-battery"
  elseif battery_supported == fields.battery_support.BATTERY_LEVEL then
    profile_name = profile_name .. "-batteryLevel"
  end
  
  device.log.info_with({hub_logs=true}, string.format("Updating soil sensor device profile to %s.", profile_name))
  device:try_update_metadata({profile = profile_name})
end


-- SOIL SENSOR LIFECYCLE HANDLERS --

local SoilSensorLifecycleHandlers = {}

function SoilSensorLifecycleHandlers.device_init(driver, device)
  device:subscribe()
end

function SoilSensorLifecycleHandlers.do_configure(driver, device)
  local battery_feature_eps = device:get_endpoints(clusters.PowerSource.ID, {feature_bitmap = clusters.PowerSource.types.PowerSourceFeature.BATTERY})
  if #battery_feature_eps > 0 then
    device:send(clusters.PowerSource.attributes.AttributeList:read())
  else
    soil_sensor_utils.match_profile(device, fields.battery_support.NO_BATTERY)
  end
end

-- CLUSTER ATTRIBUTE HANDLERS --

local sub_driver_handlers = {}

function sub_driver_handlers.power_source_attribute_list_handler(driver, device, ib, response)
  for _, attr in ipairs(ib.data.elements) do
    -- Re-profile the device if BatPercentRemaining (Attribute ID 0x0C) or
    -- BatChargeLevel (Attribute ID 0x0E) is present.
    if attr.value == 0x0C then
      soil_sensor_utils.match_profile(device, fields.battery_support.BATTERY_PERCENTAGE)
      return
    elseif attr.value == 0x0E then
      soil_sensor_utils.match_profile(device, fields.battery_support.BATTERY_LEVEL)
      return
    end
  end
end


-- SUBDRIVER TEMPLATE --

local matter_soil_sensor_handler = {
  NAME = "matter-soil-sensor",
  can_handle = soil_sensor_utils.is_matter_soil_sensor,
  lifecycle_handlers = {
    doConfigure = SoilSensorLifecycleHandlers.do_configure,
    init = SoilSensorLifecycleHandlers.device_init,
  },
  matter_handlers = {
    attr = {
      [clusters.PowerSource.ID] = {
        [clusters.PowerSource.attributes.AttributeList.ID] = sub_driver_handlers.power_source_attribute_list_handler,
      },
    }
  },
}

return matter_soil_sensor_handler
