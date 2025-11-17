-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local custom_clusters = require "MultiIR/custom_clusters"
local cluster_base = require "st.zigbee.cluster_base"

local RelativeHumidity = clusters.RelativeHumidity
local TemperatureMeasurement = clusters.TemperatureMeasurement



local function send_read_attr_request(device, cluster, attr)
  device:send(
    cluster_base.read_manufacturer_specific_attribute(
      device,
      cluster.id,
      attr.id,
      cluster.mfg_specific_code
    )
  )
end

local function do_refresh(driver, device)
  device:send(RelativeHumidity.attributes.MeasuredValue:read(device):to_endpoint(0x01))
  device:send(TemperatureMeasurement.attributes.MeasuredValue:read(device):to_endpoint(0x01))
  send_read_attr_request(device, custom_clusters.particulate_matter, custom_clusters.particulate_matter.attributes.pm2_5_MeasuredValue)
  send_read_attr_request(device, custom_clusters.particulate_matter, custom_clusters.particulate_matter.attributes.pm1_0_MeasuredValue)
  send_read_attr_request(device, custom_clusters.particulate_matter, custom_clusters.particulate_matter.attributes.pm10_MeasuredValue)
  send_read_attr_request(device, custom_clusters.unhealthy_gas, custom_clusters.unhealthy_gas.attributes.CH2O_MeasuredValue)
  send_read_attr_request(device, custom_clusters.unhealthy_gas, custom_clusters.unhealthy_gas.attributes.tvoc_MeasuredValue)
  send_read_attr_request(device, custom_clusters.carbonDioxide, custom_clusters.carbonDioxide.attributes.measured_value)
  send_read_attr_request(device, custom_clusters.AQI, custom_clusters.AQI.attributes.AQI_value)
end

local function airQualityHealthConcern_attr_handler(driver, device, value, zb_rx)
  local airQuality_level = "good"
  if value.value >= 51 then
    airQuality_level = "moderate"
  end
  if value.value >= 101 then
    airQuality_level = "slightlyUnhealthy"
  end
  if value.value >= 151 then
    airQuality_level = "unhealthy"
  end
  if value.value >= 201 then
    airQuality_level = "veryUnhealthy"
  end
  if value.value >= 301 then
    airQuality_level = "hazardous"
  end
  device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, capabilities.airQualityHealthConcern.airQualityHealthConcern({value = airQuality_level}))
end

local function carbonDioxide_attr_handler(driver, device, value, zb_rx)
  local level = "unhealthy"
  device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, capabilities.carbonDioxideMeasurement.carbonDioxide({value = value.value, unit = "ppm"}))
  if value.value <= 1500 then
    level = "good"
  elseif value.value >= 1501 and value.value <= 2500 then
    level = "moderate"
  end
  device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, capabilities.carbonDioxideHealthConcern.carbonDioxideHealthConcern({value = level}))
end

local function particulate_matter_attr_handler(cap,Concern,good,bad)
  return function(driver, device, value, zb_rx)
    local level = "unhealthy"
    device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, cap({value = value.value}))
    if value.value <= good then
      level = "good"
    elseif bad > 0 and value.value > good and value.value < bad then
      level = "moderate"
    end
    device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, Concern({value = level}))
  end
end

local function CH2O_attr_handler(driver, device, value, zb_rx)
  device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, capabilities.formaldehydeMeasurement.formaldehydeLevel({value = value.value, unit = "mg/m^3"}))
end

local function tvoc_attr_handler(driver, device, value, zb_rx)
  device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, capabilities.tvocMeasurement.tvocLevel({value = value.value, unit = "ug/m3"}))
  local level = "unhealthy"
  if value.value < 600.0 then
    level = "good"
  end
  device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, capabilities.tvocHealthConcern.tvocHealthConcern({value = level}))
end

local function added_handler(self, device)
  do_refresh()
end

local MultiIR_sensor = {
  NAME = "MultiIR air quality detector",
  lifecycle_handlers = {
    added = added_handler
  },
  zigbee_handlers = {
    attr = {
      [custom_clusters.carbonDioxide.id] = {
        [custom_clusters.carbonDioxide.attributes.measured_value.id] = carbonDioxide_attr_handler
      },
      [custom_clusters.particulate_matter.id] = {
        [custom_clusters.particulate_matter.attributes.pm2_5_MeasuredValue.id] = particulate_matter_attr_handler(capabilities.fineDustSensor.fineDustLevel,capabilities.fineDustHealthConcern.fineDustHealthConcern,75,115),--75 115 is a comparative value of good moderate unhealthy, and 0 is no comparison
        [custom_clusters.particulate_matter.attributes.pm1_0_MeasuredValue.id] = particulate_matter_attr_handler(capabilities.veryFineDustSensor.veryFineDustLevel,capabilities.veryFineDustHealthConcern.veryFineDustHealthConcern,100,0),
        [custom_clusters.particulate_matter.attributes.pm10_MeasuredValue.id] = particulate_matter_attr_handler(capabilities.dustSensor.dustLevel,capabilities.dustHealthConcern.dustHealthConcern,150,0)
      },
      [custom_clusters.unhealthy_gas.id] = {
        [custom_clusters.unhealthy_gas.attributes.CH2O_MeasuredValue.id] = CH2O_attr_handler,
        [custom_clusters.unhealthy_gas.attributes.tvoc_MeasuredValue.id] = tvoc_attr_handler
      },
      [custom_clusters.AQI.id] = {
        [custom_clusters.AQI.attributes.AQI_value.id] = airQualityHealthConcern_attr_handler
      }
    }
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    }
  },
  can_handle = require("MultiIR.can_handle"),
}

return MultiIR_sensor
