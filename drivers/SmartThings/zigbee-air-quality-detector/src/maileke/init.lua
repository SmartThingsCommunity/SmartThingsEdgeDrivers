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
local custom_clusters = require "maileke/custom_clusters"
local cluster_base = require "st.zigbee.cluster_base"

local RelativeHumidity = clusters.RelativeHumidity
local TemperatureMeasurement = clusters.TemperatureMeasurement

local MAILEKE_SENSOR_FINGERPRINTS = {
  { mfr = "MAILEKE", model = "PMT1006S-SGM-ZTN" }
}

local function can_handle_maileke_sensor(opts, driver, device)
  for _, fingerprint in ipairs(MAILEKE_SENSOR_FINGERPRINTS) do
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
  send_read_attr_request(device, custom_clusters.pm2_5, custom_clusters.pm2_5.attributes.pm2_5)
  send_read_attr_request(device, custom_clusters.pm2_5, custom_clusters.pm2_5.attributes.pm1_0)
  send_read_attr_request(device, custom_clusters.pm2_5, custom_clusters.pm2_5.attributes.pm10)
  send_read_attr_request(device, custom_clusters.CH2O, custom_clusters.CH2O.attributes.CH2O)
  send_read_attr_request(device, custom_clusters.CH2O, custom_clusters.CH2O.attributes.tvoc)
  send_read_attr_request(device, custom_clusters.carbonDioxide, custom_clusters.carbonDioxide.attributes.measured_value)
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
  end
end

local function pm2_5_attr_handler(cap,Concern,good,bad)
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

local function CH2O_attr_handler(cap, t_unit)
  return function(driver, device, value, zb_rx)
    device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, cap({value = value.value, unit = t_unit}))
  end
end

local maileke_sensor = {
  NAME = "maileke air quality detector",
  zigbee_handlers = {
    attr = {
      [custom_clusters.carbonDioxide.id] = {
        [custom_clusters.carbonDioxide.attributes.measured_value.id] = carbonDioxide_attr_handler()
      },
      [custom_clusters.pm2_5.id] = {
        [custom_clusters.pm2_5.attributes.pm2_5.id] = pm2_5_attr_handler(capabilities.fineDustSensor.fineDustLevel,capabilities.fineDustHealthConcern.fineDustHealthConcern,75,115),
        [custom_clusters.pm2_5.attributes.pm1_0.id] = pm2_5_attr_handler(capabilities.veryFineDustSensor.veryFineDustLevel,capabilities.veryFineDustHealthConcern.veryFineDustHealthConcern,100,0),
        [custom_clusters.pm2_5.attributes.pm10.id] = pm2_5_attr_handler(capabilities.dustSensor.dustLevel,capabilities.dustHealthConcern.dustHealthConcern,150,0)
      },
      [custom_clusters.CH2O.id] = {
        [custom_clusters.CH2O.attributes.CH2O.id] = CH2O_attr_handler(capabilities.formaldehydeMeasurement.formaldehydeLevel,"mg/m^3"),
        [custom_clusters.CH2O.attributes.tvoc.id] = CH2O_attr_handler(capabilities.tvocMeasurement.tvocLevel,"ug/m3")
      }
    }
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    }
  },
  can_handle = can_handle_maileke_sensor
}

return maileke_sensor
