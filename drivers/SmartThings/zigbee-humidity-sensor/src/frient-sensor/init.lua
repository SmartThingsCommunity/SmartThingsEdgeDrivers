-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local zcl_clusters = require "st.zigbee.zcl.clusters"
local HumidityMeasurement = zcl_clusters.RelativeHumidity
local TemperatureMeasurement = zcl_clusters.TemperatureMeasurement

local function device_init(driver, device)
  local configurationMap = require "configurations"
  local battery_defaults = require "st.zigbee.defaults.battery_defaults"
  battery_defaults.build_linear_voltage_init(2.3,3.0)(driver, device)
  local configuration = configurationMap.get_device_configuration(device)
  if configuration ~= nil then
    for _, attribute in ipairs(configuration) do
      device:add_configured_attribute(attribute)
    end
  end
end

local function do_configure(driver, device, event, args)
  device:configure()
  device.thread:call_with_delay(5, function()
    device:refresh()
  end)
end

local function info_changed(driver, device, event, args)
  for name, value in pairs(device.preferences) do
    if (device.preferences[name] ~= nil and args.old_st_store.preferences[name] ~= device.preferences[name]) then
      local sensitivity = math.floor((device.preferences[name]) * 100 + 0.5)
      if (name == "temperatureSensitivity") then
        device:send(TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(device, 30, 3600, sensitivity))
      end
      if (name == "humiditySensitivity") then
        device:send(HumidityMeasurement.attributes.MeasuredValue:configure_reporting(device, 60, 3600, sensitivity))
      end
    end
  end
  device.thread:call_with_delay(5, function()
      device:refresh()
  end)
end

local frient_sensor = {
  NAME = "Frient Humidity Sensor",
  lifecycle_handlers = {
    init = device_init,
    doConfigure = do_configure,
    infoChanged = info_changed
  },
  sub_drivers = require("frient-sensor.sub_drivers"),
  can_handle = require("frient-sensor.can_handle"),
}

return frient_sensor
