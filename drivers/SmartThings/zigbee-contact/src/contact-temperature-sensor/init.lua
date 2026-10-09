-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0



local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local configurationMap = require "configurations"



local function device_init(driver, device)
  local configuration = configurationMap.get_device_configuration(device)

  battery_defaults.build_linear_voltage_init(2.1, 3.0)(driver, device)

  if configuration ~= nil then
    for _, attribute in ipairs(configuration) do
      device:add_configured_attribute(attribute)
    end
  end
end

local contact_temperature_sensor = {
  NAME = "Contact Temperature Sensor",
  lifecycle_handlers = {
    init = device_init
  },
  sub_drivers = require("contact-temperature-sensor.sub_drivers"),
  can_handle = require("contact-temperature-sensor.can_handle"),
}

return contact_temperature_sensor
