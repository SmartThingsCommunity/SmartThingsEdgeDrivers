-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
local device_management = require "st.zigbee.device_management"
local utils = require "st.utils"
local zcl_clusters = require "st.zigbee.zcl.clusters"

local PowerConfiguration = zcl_clusters.PowerConfiguration
local RelativeHumidity = zcl_clusters.RelativeHumidity
local TemperatureMeasurement = zcl_clusters.TemperatureMeasurement



local battery_mains_voltage_attr_handler = function(driver, device, value, zb_rx)
  local min = 2500
  local percent = utils.round((value.value - min) / 5)
  -- Make sure our percentage is between 0 - 100
  percent = utils.clamp_value(percent, 0, 100)
  device:emit_event(capabilities.battery.battery(percent))
end

local do_refresh = function(self, device)
  local attributes = {
    PowerConfiguration.attributes.MainsVoltage,
    RelativeHumidity.attributes.MeasuredValue,
    TemperatureMeasurement.attributes.MeasuredValue
  }
  for _, attribute in pairs(attributes) do
    device:send(attribute:read(device))
  end
end

local device_added = function(self, device)
  do_refresh(self, device)
end

local do_configure = function(self, device)
  device:send(device_management.build_bind_request(device, PowerConfiguration.ID, self.environment_info.hub_zigbee_eui))
  device:send(device_management.build_bind_request(device, RelativeHumidity.ID, self.environment_info.hub_zigbee_eui))
  device:send(device_management.build_bind_request(device, TemperatureMeasurement.ID, self.environment_info.hub_zigbee_eui))
  device:send(RelativeHumidity.attributes.MeasuredValue:configure_reporting(device, 10, 610, 6400))
  device:send(TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(device, 1, 0, 3200))
  device:send(PowerConfiguration.attributes.MainsVoltage:configure_reporting(device, 0x0C, 0, 500))
end

local plaid_systems_humdity_sensor = {
  NAME = "PLAID Systems Humidity Sensor",
  lifecycle_handlers = {
    added = device_added,
    doConfigure = do_configure
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    }
  },
  zigbee_handlers = {
    attr = {
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.MainsVoltage.ID] = battery_mains_voltage_attr_handler
      }
    }
  },
  can_handle = require("plaid-systems.can_handle"),
}

return plaid_systems_humdity_sensor
