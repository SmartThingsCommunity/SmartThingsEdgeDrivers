-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local util = require "st.utils"
local data_types = require "st.zigbee.data_types"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local TemperatureMeasurement = zcl_clusters.TemperatureMeasurement
local HumidityMeasurement = zcl_clusters.RelativeHumidity
local PowerConfiguration = zcl_clusters.PowerConfiguration
local device_management = require "st.zigbee.device_management"
local cluster_base = require "st.zigbee.cluster_base"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local configurationMap = require "configurations"

local FRIENT_AIR_QUALITY_SENSOR_FINGERPRINTS = {
  { mfr = "frient A/S", model = "AQSZB-110", subdriver = "airquality" }
}

local function can_handle_frient(opts, driver, device, ...)
  for _, fingerprint in ipairs(FRIENT_AIR_QUALITY_SENSOR_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model and fingerprint.subdriver == "airquality" then
      return true
    end
  end
  return false
end

local Frient_VOCMeasurement = {
  ID = 0xFC03,
  ManufacturerSpecificCode = 0x1015,
  attributes = {
    MeasuredValue = { ID = 0x0000, base_type = data_types.Uint16 },
    MinMeasuredValue = { ID = 0x0001, base_type = data_types.Uint16 },
    MaxMeasuredValue = { ID = 0x0002, base_type = data_types.Uint16 },
    Resolution = { ID = 0x0003, base_type = data_types.Uint16 },
  },
}

Frient_VOCMeasurement.attributes.MeasuredValue._cluster = Frient_VOCMeasurement
Frient_VOCMeasurement.attributes.MinMeasuredValue._cluster = Frient_VOCMeasurement
Frient_VOCMeasurement.attributes.MaxMeasuredValue._cluster = Frient_VOCMeasurement
Frient_VOCMeasurement.attributes.Resolution._cluster = Frient_VOCMeasurement

local MAX_VOC_REPORTABLE_VALUE = 5500 -- Max VOC reportable value

--- Table to map VOC (ppb) to HealthConcern
local VOC_TO_HEALTHCONCERN_MAPPING = {
  [2201] = "veryUnhealthy",
  [661] = "unhealthy",
  [221] = "slightlyUnhealthy",
  [66] = "moderate",
  [0] = "good",
}

--- Map VOC (ppb) to HealthConcern
local function voc_to_healthconcern(raw_voc)
  for voc, perc in util.rkeys(VOC_TO_HEALTHCONCERN_MAPPING) do
    if raw_voc >= voc then
      return perc
    end
  end
end
--- Map VOC (ppb) to CAQI
local function voc_to_caqi(raw_voc)
  if (raw_voc > 5500) then
    return 100
  else
    return math.floor(raw_voc*99/5500)
  end
end

-- May take around 8 minutes for the first valid VOC measurement to be reported after the device is powered on
local function voc_measure_value_attr_handler(driver, device, attr_val, zb_rx)
  local voc_value = attr_val.value
  if (voc_value < 65535) then -- ignore it if it's outside the limits
    voc_value = util.clamp_value(voc_value, 0, MAX_VOC_REPORTABLE_VALUE)
    device:emit_event(capabilities.airQualitySensor.airQuality({ value = voc_to_caqi(voc_value)}))
    device:emit_event(capabilities.tvocHealthConcern.tvocHealthConcern(voc_to_healthconcern(voc_value)))
    device:emit_event(capabilities.tvocMeasurement.tvocLevel({ value = voc_value, unit = "ppb" }))
  end
end

-- The device sends the value of MeasuredValue to be 0x8000, which corresponds to -327.68C, until it gets the first valid measurement. Therefore we don't emit event before the value is correct. It may take up to 4 minutes
local function temperatureHandler(driver, device, attr_val, zb_rx)
  local temp_value = attr_val.value
  if (temp_value > -32768) then
    device:emit_event(capabilities.temperatureMeasurement.temperature({ value = temp_value / 100, unit = "C" }))
  end
end

local function device_init(driver, device)
  battery_defaults.build_linear_voltage_init(2.3, 3.0)(driver, device)
  local configuration = configurationMap.get_device_configuration(device)
  if configuration ~= nil then
    for _, attribute in ipairs(configuration) do
      device:add_configured_attribute(attribute)
    end
  end
end

local function device_added(driver, device)
  device:emit_event(capabilities.airQualitySensor.airQuality(voc_to_caqi(0)))
  device:emit_event(capabilities.tvocHealthConcern.tvocHealthConcern(voc_to_healthconcern(0)))
  device:emit_event(capabilities.tvocMeasurement.tvocLevel({ value = 0, unit = "ppb" }))
end

local function do_refresh(driver, device)
  for _, fingerprint in ipairs(FRIENT_AIR_QUALITY_SENSOR_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      device:send(cluster_base.read_manufacturer_specific_attribute(device, Frient_VOCMeasurement.ID, Frient_VOCMeasurement.attributes.MeasuredValue.ID, Frient_VOCMeasurement.ManufacturerSpecificCode):to_endpoint(0x26))
      device:send(TemperatureMeasurement.attributes.MeasuredValue:read(device):to_endpoint(0x26))
      device:send(HumidityMeasurement.attributes.MeasuredValue:read(device):to_endpoint(0x26))
      device:send(PowerConfiguration.attributes.BatteryVoltage:read(device))
    end
  end
end

local function do_configure(driver, device)
  device:configure()
  device:send(device_management.build_bind_request(device, Frient_VOCMeasurement.ID, driver.environment_info.hub_zigbee_eui, 0x26))

  device:send(
          cluster_base.configure_reporting(
                  device,
                  data_types.ClusterId(Frient_VOCMeasurement.ID),
                  Frient_VOCMeasurement.attributes.MeasuredValue.ID,
                  Frient_VOCMeasurement.attributes.MeasuredValue.base_type.ID,
                  60, 600, 10
          ):to_endpoint(0x26)
  )

  device.thread:call_with_delay(5, function()
    do_refresh(driver, device)
  end)
end

local frient_airquality_sensor = {
  NAME = "frient Air Quality Sensor",
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    doConfigure = do_configure,
  },
  zigbee_handlers = {
    cluster = {},
    attr = {
      [Frient_VOCMeasurement.ID] = {
        [Frient_VOCMeasurement.attributes.MeasuredValue.ID] = voc_measure_value_attr_handler,
      },
      [TemperatureMeasurement.ID] = {
        [TemperatureMeasurement.attributes.MeasuredValue.ID] = temperatureHandler,
      },
    }
  },
  can_handle = can_handle_frient
}

return frient_airquality_sensor