-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"

local OnOff = clusters.OnOff
local Level = clusters.Level
local ColorControl = clusters.ColorControl


local function do_refresh(driver, device)
  local attributes = {
  OnOff.attributes.OnOff,
  Level.attributes.CurrentLevel,
  ColorControl.attributes.CurrentHue,
  ColorControl.attributes.CurrentSaturation
  }
  for _, attribute in pairs(attributes) do
    device:send(attribute:read(device))
  end
end

local function do_configure(driver, device)
  device:configure()
  do_refresh(driver, device)
end

local rgb_bulb = {
  NAME = "RGB Bulb",
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    }
  },
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  can_handle = require("rgb-bulb.can_handle"),
}

return rgb_bulb
