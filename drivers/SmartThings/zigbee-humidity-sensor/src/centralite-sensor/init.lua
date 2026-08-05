-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local device_management = require "st.zigbee.device_management"
local utils = require "st.utils"
local configurationMap = require "configurations"

local HUMIDITY_CLUSTER_ID = 0xFC45
local HUMIDITY_MEASURE_ATTR_ID = 0x0000



local function device_init(driver, device)
  device:remove_configured_attribute(clusters.RelativeHumidity.ID, clusters.RelativeHumidity.attributes.MeasuredValue.ID)
  device:remove_monitored_attribute(clusters.RelativeHumidity.ID, clusters.RelativeHumidity.attributes.MeasuredValue.ID)

  battery_defaults.build_linear_voltage_init(2.1, 3.0)(driver, device)
end

local function do_refresh(driver, device)
  device:refresh()
  device:send(cluster_base.read_manufacturer_specific_attribute(device, HUMIDITY_CLUSTER_ID, HUMIDITY_MEASURE_ATTR_ID, 0x104E))
  device:send(cluster_base.read_manufacturer_specific_attribute(device, HUMIDITY_CLUSTER_ID, HUMIDITY_MEASURE_ATTR_ID, 0xC2DF))
end

local function do_configure(driver, device)
  local configuration = configurationMap.get_device_configuration(device)

  device:configure()
  device:send(device_management.build_bind_request(device, HUMIDITY_CLUSTER_ID, driver.environment_info.hub_zigbee_eui))

  if configuration ~= nil then
    for _, attribute in ipairs(configuration) do
      device:send(device_management.attr_config(device, attribute))
    end
  end

  do_refresh(driver, device)
end

local function custom_humidity_measure_attr_handler(driver, device, value, zb_rx)
  local humidity_value = utils.round(value.value / 100)
  device:emit_event(capabilities.relativeHumidityMeasurement.humidity(humidity_value))
end

local centralite_sensor = {
  NAME = "CentraLite Humidity Sensor",
  lifecycle_handlers = {
    init = device_init,
    doConfigure = do_configure
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    }
  },
  zigbee_handlers = {
    attr = {
      [HUMIDITY_CLUSTER_ID] = {
        [HUMIDITY_MEASURE_ATTR_ID] = custom_humidity_measure_attr_handler
      }
    }
  },
  can_handle = require("centralite-sensor.can_handle"),
}

return centralite_sensor
