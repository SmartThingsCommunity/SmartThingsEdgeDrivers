-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"

local Level = clusters.Level

local function handle_set_level(driver, device, cmd)
  local level = math.floor(cmd.args.level/100.0 * 254)
  local transtition_time = cmd.args.rate or 0xFFFF
  local command = Level.server.commands.MoveToLevelWithOnOff(device, level, transtition_time)

  command.body.zcl_body.options_mask = nil
  command.body.zcl_body.options_override = nil
  device:send(command)
end

local duragreen_color_temp_bulb = {
  NAME = "DuraGreen Color Temp Bulb",
  capability_handlers = {
    [capabilities.switchLevel.ID] = {
      [capabilities.switchLevel.commands.setLevel.NAME] = handle_set_level
    }
  },
  can_handle = require("white-color-temp-bulb.duragreen.can_handle")
}

return duragreen_color_temp_bulb
