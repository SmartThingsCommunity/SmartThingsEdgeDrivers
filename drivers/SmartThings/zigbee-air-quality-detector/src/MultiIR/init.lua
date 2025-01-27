-- Copyright 2024 SmartThings
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

local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local custom_clusters = require "MultiIR/custom_clusters"
local cluster_base = require "st.zigbee.cluster_base"

local RelativeHumidity = clusters.RelativeHumidity
local TemperatureMeasurement = clusters.TemperatureMeasurement

local MultiIR_SENSOR_FINGERPRINTS = {
  { mfr = "MultiIR", model = "PMT1006S-SGM-ZTN" }--This is not a sleep end device
}

local function can_handle_MultiIR_sensor(opts, driver, device)
  for _, fingerprint in ipairs(MultiIR_SENSOR_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

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
end

local LEVEL_TO_NUMBER = {
  { level = "good", value = 1 },
  { level = "moderate", value = 2 },
  { level = "unhealthy", value = 3 }
}

local cap_index = {
  carbonDioxide = 1,
  pm2_5 = 2,
  pm1_0 = 3,
  pm10 = 4,
  tvoc = 5
}

local cap_save_level = {
  { level = "good", value = 1 },
  { level = "good", value = 1 },
  { level = "good", value = 1 },
  { level = "good", value = 1 },
  { level = "good", value = 1 }
}

local function airQualityHealthConcern_handler(device,ep,index,level)
  --local airQuality_level = "unhealthy"
  local max = 1
  local max_cap = 3
  --level is converted to a number and save it
  for _,value in ipairs(LEVEL_TO_NUMBER) do
    if level == value.level then
      cap_save_level[index].value = value.value
      cap_save_level[index].level = level
    end
  end
  --Find the maximal of all levels
  for i=1,5 do
    if cap_save_level[i].value > max then
      max = cap_save_level[i].value;
      max_cap = i
    end
  end
  --The maximum value represents the air quality class
  local airQuality_level = cap_save_level[max_cap].level
  device:emit_event_for_endpoint(ep, capabilities.airQualityHealthConcern.airQualityHealthConcern({value = airQuality_level}))
end

local function carbonDioxide_attr_handler()
  return function(driver, device, value, zb_rx)
    local level = "unhealthy"
    device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, capabilities.carbonDioxideMeasurement.carbonDioxide({value = value.value, unit = "ppm"}))
    if value.value <= 1500 then
      level = "good"
    elseif value.value >= 1501 and value.value <= 2500 then
      level = "moderate"
    end
      device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, capabilities.carbonDioxideHealthConcern.carbonDioxideHealthConcern({value = level}))
      airQualityHealthConcern_handler(device,zb_rx.address_header.src_endpoint.value,cap_index.carbonDioxide,level)
    end
end

local function particulate_matter_attr_handler(save_cap,cap,Concern,good,bad)
  return function(driver, device, value, zb_rx)
    local level = "unhealthy"
    device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, cap({value = value.value}))
    if value.value <= good then
      level = "good"
    elseif bad > 0 and value.value > good and value.value < bad then
      level = "moderate"
    end
      device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, Concern({value = level}))
      airQualityHealthConcern_handler(device,zb_rx.address_header.src_endpoint.value,save_cap,level)
    end
end

local function CH2O_attr_handler(cap, t_unit)
  return function(driver, device, value, zb_rx)
    device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, cap({value = value.value, unit = t_unit}))
  end
end

local function tvoc_attr_handler(cap,Concern, t_unit)
  return function(driver, device, value, zb_rx)
    device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, cap({value = value.value, unit = t_unit}))
    local level = "unhealthy"
    if value.value < 600.0 then
      level = "good"
    end
    device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, Concern({value = level}))
    airQualityHealthConcern_handler(device,zb_rx.address_header.src_endpoint.value,cap_index.tvoc,level)
  end
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
        [custom_clusters.carbonDioxide.attributes.measured_value.id] = carbonDioxide_attr_handler()
      },
      [custom_clusters.particulate_matter.id] = {
        [custom_clusters.particulate_matter.attributes.pm2_5_MeasuredValue.id] = particulate_matter_attr_handler(cap_index.pm2_5,capabilities.fineDustSensor.fineDustLevel,capabilities.fineDustHealthConcern.fineDustHealthConcern,75,115),--75 115 is a comparative value of good moderate unhealthy, and 0 is no comparison
        [custom_clusters.particulate_matter.attributes.pm1_0_MeasuredValue.id] = particulate_matter_attr_handler(cap_index.pm1_0,capabilities.veryFineDustSensor.veryFineDustLevel,capabilities.veryFineDustHealthConcern.veryFineDustHealthConcern,100,0),
        [custom_clusters.particulate_matter.attributes.pm10_MeasuredValue.id] = particulate_matter_attr_handler(cap_index.pm10,capabilities.dustSensor.dustLevel,capabilities.dustHealthConcern.dustHealthConcern,150,0)
      },
      [custom_clusters.unhealthy_gas.id] = {
        [custom_clusters.unhealthy_gas.attributes.CH2O_MeasuredValue.id] = CH2O_attr_handler(capabilities.formaldehydeMeasurement.formaldehydeLevel,"mg/m^3"),
        [custom_clusters.unhealthy_gas.attributes.tvoc_MeasuredValue.id] = tvoc_attr_handler(capabilities.tvocMeasurement.tvocLevel,capabilities.tvocHealthConcern.tvocHealthConcern,"ug/m3")
      }
    }
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    }
  },
  can_handle = can_handle_MultiIR_sensor
}

return MultiIR_sensor
