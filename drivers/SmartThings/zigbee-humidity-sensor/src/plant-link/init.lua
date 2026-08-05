-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local zcl_clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local PowerConfiguration = zcl_clusters.PowerConfiguration
local RelativeHumidity = zcl_clusters.RelativeHumidity
local utils = require "st.utils"



local humidity_value_attr_handler = function(driver, device, value, zb_rx)
  -- adc reading of 0x1ec0 produces a plant fuel level near 0
  -- adc reading of 0x2100 produces a plant fuel level near 100%
  local HUMIDITY_VALUE_MAX = 0x2100
  local HUMIDITY_VALUE_MIN = 0x1EC0
  local humidity_value = value.value
  local percent = ((humidity_value - HUMIDITY_VALUE_MIN) / (HUMIDITY_VALUE_MAX - HUMIDITY_VALUE_MIN)) *100
  percent = utils.clamp_value(percent, 0.0, 100.0)
  device:emit_event(capabilities.relativeHumidityMeasurement.humidity(percent))
end

local battery_mains_voltage_attr_handler = function(driver, device, value, zb_rx)
  local min = 2300
  local percent = (value.value - min) /10
  -- Make sure our percentage is between 0 - 100
  percent = utils.clamp_value(percent, 0.0, 100.0)
  device:emit_event(capabilities.battery.battery(percent))
end


local plant_link_humdity_sensor = {
  NAME = "PlantLink Soil Moisture Sensor",
  supported_capabilities = {
    capabilities.relativeHumidityMeasurement,
    capabilities.battery,
  },
  zigbee_handlers = {
    attr = {
      [RelativeHumidity.ID] = {
        [RelativeHumidity.attributes.MeasuredValue.ID] = humidity_value_attr_handler
      },
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.MainsVoltage.ID] = battery_mains_voltage_attr_handler
      }
    }
  },
  can_handle = require("plant-link.can_handle"),
}

return plant_link_humdity_sensor
