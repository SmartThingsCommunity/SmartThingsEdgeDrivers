-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local zcl_clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"

local OnOff = zcl_clusters.OnOff

local function switch_on_handler(driver, device, command)
  device:send_to_component(command.component, OnOff.server.commands.On(device))
  device:send(OnOff.server.commands.On(device):to_endpoint(0x02))
end

local function switch_off_handler(driver, device, command)
  device:send_to_component(command.component, OnOff.server.commands.Off(device))
  device:send(OnOff.server.commands.Off(device):to_endpoint(0x02))
end


local zigbee_metering_plug = {
  NAME = "zigbee metering plug",
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = switch_on_handler,
      [capabilities.switch.commands.off.NAME] = switch_off_handler
    }
  },
  can_handle = require("rexense.can_handle"),
}

return zigbee_metering_plug
