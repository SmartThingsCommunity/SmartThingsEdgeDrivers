-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local device_management = require "st.zigbee.device_management"

local OnOff = clusters.OnOff
local button = capabilities.button.button



local function do_configure(driver, device)
  device:configure()
  device:send(device_management.build_bind_request(device, OnOff.ID, driver.environment_info.hub_zigbee_eui))
end

local function button_handler(event)
  return function(driver, device, value, zb_rx)
    device:emit_event(event)
  end
end

local ewelink_button = {
  NAME = "eWeLink Button",
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  zigbee_handlers = {
    cluster = {
      [OnOff.ID] = {
        [OnOff.server.commands.On.ID] = button_handler(button.double({ state_change = true })),
        [OnOff.server.commands.Off.ID] = button_handler(button.held({ state_change = true })),
        [OnOff.server.commands.OffWithEffect.ID] = button_handler(button.pushed({ state_change = true })),
        [OnOff.server.commands.OnWithRecallGlobalScene.ID] = button_handler(button.pushed({ state_change = true })),
        [OnOff.server.commands.OnWithTimedOff.ID] = button_handler(button.pushed({ state_change = true })),
        [OnOff.server.commands.Toggle.ID] = button_handler(button.pushed({ state_change = true }))
      }
    }
  },
  can_handle = require("ewelink.can_handle"),
}

return ewelink_button
