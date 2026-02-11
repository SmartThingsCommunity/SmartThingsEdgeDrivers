-- Copyright 2023 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
local clusters  = require "st.zigbee.zcl.clusters"
local device_management = require "st.zigbee.device_management"
local log = require "log"
local Level = clusters.Level
local OnOff = clusters.OnOff
local ColorControl = clusters.ColorControl

local emit_pushed_event = function(button_name, device)
  local additional_fields = {
    state_change = true
  }
  local event = capabilities.button.button.pushed(additional_fields)
  local comp = device.profile.components[button_name]
  if comp ~= nil then
    device:emit_component_event(comp, event)
  else
    log.warn("Attempted to emit button event for unknown button: " .. button_name)
  end
end

local emit_held_event = function(button_name, device)
  local additional_fields = {
    state_change = true
  }
  local event = capabilities.button.button.held(additional_fields)
  local comp = device.profile.components[button_name]
  if comp ~= nil then
    device:emit_component_event(comp, event)
  else
    log.warn("Attempted to emit button event for unknown button: " .. button_name)
  end
end

local do_configure = function(self, device)
  device:send(device_management.build_bind_request(device, OnOff.ID, self.environment_info.hub_zigbee_eui))
  -- The device reports button presses to this group but it can't be read from the binding table
end

local SLED_button = {
  NAME = "SLED Button",
  zigbee_handlers = {
    cluster = {
      [OnOff.ID] = {
        [OnOff.server.commands.Off.ID] = function(driver, device, zb_rx) emit_pushed_event("button2", device) end,
        [OnOff.server.commands.On.ID] = function(driver, device, zb_rx) emit_pushed_event("button1", device) end,
        [OnOff.server.commands.Toggle.ID] = function(driver, device, zb_rx) emit_pushed_event("button3", device) end
      },
      [Level.ID] = {
        [Level.server.commands.Move.ID] = function(driver, device, zb_rx) emit_held_event("button2", device) end,
        [Level.server.commands.MoveWithOnOff.ID] = function(driver, device, zb_rx) emit_held_event("button1", device) end
      },
      [ColorControl.ID] = {
        [ColorControl.server.commands.MoveToColorTemperature.ID] = function(driver, device, zb_rx) emit_held_event("button3", device) end
      }
    }
  },
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  can_handle = require("zigbee-multi-button.SLED.can_handle"),
}

return SLED_button
