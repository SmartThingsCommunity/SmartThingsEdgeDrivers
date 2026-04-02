-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local colorTemperature_defaults = require "st.zigbee.defaults.colorTemperature_defaults"

local ColorControl = clusters.ColorControl

local function set_color_temperature_handler(driver, device, cmd)
  colorTemperature_defaults.set_color_temperature(driver, device, cmd)

  device.thread:call_with_delay(1, function(d)
    device:send(ColorControl.attributes.ColorTemperatureMireds:read(device))
  end)
end

local white_color_temp_bulb = {
  NAME = "White Color Temp Bulb",
  capability_handlers = {
    [capabilities.colorTemperature.ID] = {
      [capabilities.colorTemperature.commands.setColorTemperature.NAME] = set_color_temperature_handler
    }
  },
  sub_drivers = require("white-color-temp-bulb.sub_drivers"),
  can_handle = require("white-color-temp-bulb.can_handle"),
}

return white_color_temp_bulb
