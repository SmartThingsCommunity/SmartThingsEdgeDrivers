-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"

local OnOff = clusters.OnOff
local Level = clusters.Level

local SwitchLevel = capabilities.switchLevel

local function set_switch_level_handler(driver, device, cmd)
  local level = math.floor(cmd.args.level / 100.0 * 254)

  device:send(Level.server.commands.MoveToLevelWithOnOff(device, level, cmd.args.rate or 0xFFFF))
  if(level > 0) then
    device:send(OnOff.server.commands.On(device))
  end
end

local osram_iqbr30 = {
  NAME = "Zigbee Osram iQBR30 Dimmer",
  capability_handlers = {
    [SwitchLevel.ID] = {
      [SwitchLevel.commands.setLevel.NAME] = set_switch_level_handler
    }
  },
  can_handle = require("zigbee-dimming-light.osram-iqbr30.can_handle"),
}

return osram_iqbr30
