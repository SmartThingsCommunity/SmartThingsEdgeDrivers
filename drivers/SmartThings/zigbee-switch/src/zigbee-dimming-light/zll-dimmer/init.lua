-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"

local Level = clusters.Level

local SwitchLevel = capabilities.switchLevel

local function set_switch_level_handler(driver, device, cmd)
  local level = math.floor(cmd.args.level / 100.0 * 254)

  device:send(Level.server.commands.MoveToLevelWithOnOff(device, level, cmd.args.rate or 0xFFFF))
  device:refresh()
end

local zll_dimmer = {
  NAME = "Zigbee Leviton Dimmer",
  capability_handlers = {
    [SwitchLevel.ID] = {
      [SwitchLevel.commands.setLevel.NAME] = set_switch_level_handler
    }
  },
  can_handle = require("zigbee-dimming-light.zll-dimmer.can_handle")
}

return zll_dimmer
