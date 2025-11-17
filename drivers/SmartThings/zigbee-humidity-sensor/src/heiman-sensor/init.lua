-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local device_management = require "st.zigbee.device_management"

local RelativeHumidity = clusters.RelativeHumidity
local TemperatureMeasurement = clusters.TemperatureMeasurement
local PowerConfiguration = clusters.PowerConfiguration



local function do_refresh(driver, device)
  device:send(RelativeHumidity.attributes.MeasuredValue:read(device):to_endpoint(0x02))
  device:send(TemperatureMeasurement.attributes.MeasuredValue:read(device))
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:read(device))
end

local function do_configure(driver, device)
  device:send(device_management.build_bind_request(device, RelativeHumidity.ID, driver.environment_info.hub_zigbee_eui):to_endpoint(0x02))
  device:configure()
  device:send(RelativeHumidity.attributes.MeasuredValue:configure_reporting(device, 30, 3600, 100):to_endpoint(0x02))
  do_refresh(driver, device)
end

local heiman_sensor = {
  NAME = "Heiman Humidity Sensor",
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    }
  },
  can_handle = require("heiman-sensor.can_handle"),
}

return heiman_sensor
