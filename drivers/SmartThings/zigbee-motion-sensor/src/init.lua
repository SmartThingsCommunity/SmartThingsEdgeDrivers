-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"
local constants = require "st.zigbee.constants"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local lazy_load_if_possible = require "lazy_load_subdriver"

local temperature_measurement_defaults = {
  MIN_TEMP = "MIN_TEMP",
  MAX_TEMP = "MAX_TEMP"
}

local HAS_RECONFIGURED = "_has_reconfigured"

--- Default handler for Temperature min and max measured value on the Temperature measurement cluster
---
--- This starts initially by performing the same conversion in the temperature_measurement_attr_handler function.
--- It then sets the field of whichever measured value is defined by the @param and checks if the fields
--- correctly compare
---
--- @param minOrMax string the string that determines which attribute to set
--- @param driver Driver The current driver running containing necessary context for execution
--- @param device ZigbeeDevice The device this message was received from containing identifying information
--- @param value Int16 the value of the measured temperature
--- @param zb_rx containing the full message this report came in

local temperature_measurement_min_max_attr_handler = function(minOrMax)
  return function(driver, device, value, zb_rx)
    local raw_temp = value.value
    local celc_temp = raw_temp / 100.0
    local temp_scale = "C"

    device:set_field(string.format("%s", minOrMax), celc_temp)

    local min = device:get_field(temperature_measurement_defaults.MIN_TEMP)
    local max = device:get_field(temperature_measurement_defaults.MAX_TEMP)

    if min ~= nil and max ~= nil then
      if min < max then
        device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, capabilities.temperatureMeasurement.temperatureRange({ value = { minimum = min, maximum = max }, unit = temp_scale }))
        device:set_field(temperature_measurement_defaults.MIN_TEMP, nil)
        device:set_field(temperature_measurement_defaults.MAX_TEMP, nil)
      else
        device.log.warn_with({hub_logs = true}, string.format("Device reported a min temperature %d that is not lower than the reported max temperature %d", min, max))
      end
    end
  end
end

-- TODO: Remove when available in lua libs
-- This is a temporary method to lower battery consumption in several devices.
-- Disparities were noted between DTH implementations and driver defaults. -sg
local do_refresh = function(driver, device, command)
  device:refresh()

  if device:get_field(HAS_RECONFIGURED) == nil then
    if device:supports_capability_by_id(capabilities.temperatureMeasurement.ID) and device:supports_server_cluster(zcl_clusters.TemperatureMeasurement.ID) then
      device:send(zcl_clusters.TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(device, 30, 600, 100))
    end

    if device:supports_capability_by_id(capabilities.motionSensor.ID) and device:supports_server_cluster(zcl_clusters.IASZone.ID) then
      device:send(zcl_clusters.IASZone.attributes.ZoneStatus:configure_reporting(device, 0xFFFF, 0x0000, 0)) -- reset to default
    end
    device:set_field(HAS_RECONFIGURED, true)
  end
end

local added_handler = function(self, device)
  device:send(zcl_clusters.TemperatureMeasurement.attributes.MinMeasuredValue:read(device))
  device:send(zcl_clusters.TemperatureMeasurement.attributes.MaxMeasuredValue:read(device))
end

local zigbee_motion_driver = {
  supported_capabilities = {
    capabilities.motionSensor,
    capabilities.temperatureMeasurement,
    capabilities.relativeHumidityMeasurement,
    capabilities.battery,
    capabilities.presenceSensor,
    capabilities.contactSensor,
    capabilities.illuminanceMeasurement
  },
  zigbee_handlers = {
    attr = {
      [zcl_clusters.TemperatureMeasurement.ID] = {
        [zcl_clusters.TemperatureMeasurement.attributes.MinMeasuredValue.ID] = temperature_measurement_min_max_attr_handler(temperature_measurement_defaults.MIN_TEMP),
        [zcl_clusters.TemperatureMeasurement.attributes.MaxMeasuredValue.ID] = temperature_measurement_min_max_attr_handler(temperature_measurement_defaults.MAX_TEMP),
      }
    }
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    }
  },
  lifecycle_handlers = {
    added = added_handler
  },
  sub_drivers = {
    lazy_load_if_possible("aqara"),
    lazy_load_if_possible("aurora"),
    lazy_load_if_possible("ikea"),
    lazy_load_if_possible("iris"),
    lazy_load_if_possible("gatorsystem"),
    lazy_load_if_possible("motion_timeout"),
    lazy_load_if_possible("nyce"),
    lazy_load_if_possible("zigbee-plugin-motion-sensor"),
    lazy_load_if_possible("compacta"),
    lazy_load_if_possible("frient"),
    lazy_load_if_possible("samjin"),
    lazy_load_if_possible("battery-voltage"),
    lazy_load_if_possible("centralite"),
    lazy_load_if_possible("smartthings"),
    lazy_load_if_possible("smartsense"),
    lazy_load_if_possible("thirdreality"),
    lazy_load_if_possible("sengled"),
  },
  additional_zcl_profiles = {
    [0xFC01] = true
  },
  ias_zone_configuration_method = constants.IAS_ZONE_CONFIGURE_TYPE.AUTO_ENROLL_RESPONSE,
  health_check = false,
}
defaults.register_for_default_handlers(zigbee_motion_driver,
  zigbee_motion_driver.supported_capabilities, {native_capability_attrs_enabled = true})
local motion = ZigbeeDriver("zigbee-motion", zigbee_motion_driver)
motion:run()
