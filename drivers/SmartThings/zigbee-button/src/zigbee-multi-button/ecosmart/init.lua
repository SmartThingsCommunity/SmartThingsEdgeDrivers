-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
local clusters  = require "st.zigbee.zcl.clusters"
local device_management = require "st.zigbee.device_management"
local log = require "log"
local Level = clusters.Level
local OnOff = clusters.OnOff
local ColorControl = clusters.ColorControl
local PowerConfiguration = clusters.PowerConfiguration

--[[
The EcoSmart remote has 4 buttons. We've chosen to only support "pushed" events on all buttons even though technically
we could support "held" on buttons 2 and 3. This gives a more consistent and less confusing user experience.

Button 1
--------

The first button sends alternating On and Off commands. We translate both commands to button1 `pushed` events.

Button 2
--------

The second button sends MoveToLevel commands when pressed, Move commands when held and Stop when let go. We translate
both MoveToLevel and Move to button2 `pushed` events and ignore Stop commands.

Button 3
--------

The third button sends MoveToColorTemperature commands when pressed and MoveColorTemperature commands when held/let go.
We generate button3 `pushed` events but only if not preceded by a MoveToLevelWithOnOff.

Button 4
--------

The fourth button sends a MoveToLevelWithOnOff command followed by MoveToColorTemperature. We generate button4 `pressed`
events when we receive the MoveToLevelWithOnOff command and we ignore the following MoveToColorTemperature command so
that we don't generate an erroneous button3 `pushed` event.
--]]

local fields = {
  IGNORE_MOVETOCOLORTEMP = "ignore_next_movetocolortemperature"
}

local emit_pushed_event = function(button_name, device)
  local additional_fields = {
    state_change = true
  }
  local event = capabilities.button.button.pushed(additional_fields)
  local comp = device.profile.components[button_name]
  if comp ~= nil then
    device:emit_component_event(comp, event)
    device:emit_event(event)
  else
    log.warn("Attempted to emit button event for unknown button: " .. button_name)
  end
end

local function moveToColorTemperature_handler(driver, device, zb_rx)
  if device:get_field(fields.IGNORE_MOVETOCOLORTEMP) ~= true then
    emit_pushed_event("button3", device)
  end
  device:set_field(fields.IGNORE_MOVETOCOLORTEMP, false)
end

local function moveColorTemperature_handler(driver, device, zb_rx)
  if zb_rx.body.zcl_body.move_mode.value ~= ColorControl.types.CcMoveMode.Stop then
      emit_pushed_event("button3", device)
  end
end

local function moveToLevelWithOnOff_handler(driver, device, zb_rx)
  device:set_field(fields.IGNORE_MOVETOCOLORTEMP, true)
  emit_pushed_event("button4", device)
end

local do_refresh = function(self, device)
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:read(device))
end

local do_configure = function(self, device)
  do_refresh(self, device)
  device:send(device_management.build_bind_request(device, PowerConfiguration.ID, self.environment_info.hub_zigbee_eui))
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(device, 30, 21600, 1))
  device:send(device_management.build_bind_request(device, OnOff.ID, self.environment_info.hub_zigbee_eui))
  -- The device reports button presses to this group but it can't be read from the binding table
  self:add_hub_to_zigbee_group(0x4003)
end

local ecosmart_button = {
  NAME = "EcoSmart Button",
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    }
  },
  zigbee_handlers = {
    cluster = {
      [OnOff.ID] = {
        [OnOff.server.commands.Off.ID] = function(driver, device, zb_rx) emit_pushed_event("button1", device) end,
        [OnOff.server.commands.On.ID] = function(driver, device, zb_rx) emit_pushed_event("button1", device) end
      },
      [Level.ID] = {
        [Level.server.commands.MoveToLevel.ID] = function(driver, device, zb_rx) emit_pushed_event("button2", device) end,
        [Level.server.commands.Move.ID] = function(driver, device, zb_rx) emit_pushed_event("button2", device) end,
        [Level.server.commands.MoveToLevelWithOnOff.ID] = moveToLevelWithOnOff_handler
      },
      [ColorControl.ID] = {
        [ColorControl.server.commands.MoveToColorTemperature.ID] = moveToColorTemperature_handler,
        [ColorControl.server.commands.MoveColorTemperature.ID] = moveColorTemperature_handler,
      }
    }
  },
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  can_handle = require("zigbee-multi-button.ecosmart.can_handle"),
}

return ecosmart_button
