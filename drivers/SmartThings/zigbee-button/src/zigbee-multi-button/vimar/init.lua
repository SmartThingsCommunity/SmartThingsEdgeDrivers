-- Copyright 2024 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
local clusters  = require "st.zigbee.zcl.clusters"
local device_management = require "st.zigbee.device_management"
local OnOff = clusters.OnOff
local LevelControl = clusters.Level
local log = require "log"

local VIMAR_HOLD_BUTTON = "Vimar_Holding_Button"

local emit_button_event = function(button_name, device, event)
  local comp = device.profile.components[button_name]
  if comp ~= nil then
    device:emit_component_event(comp, event)
    device:emit_event(event)
  else
    log.warn("Attempted to emit button event for unknown button: " .. button_name)
  end
end

local function vimar_up_button_pushed(driver, device, zb_rx)
  emit_button_event("button1", device, capabilities.button.button.pushed({state_change = true}))
end

local function vimar_down_button_pushed(driver, device, zb_rx)
  emit_button_event("button2", device, capabilities.button.button.pushed({state_change = true}))
end

local function vimar_button_hold(driver, device, zb_rx)
  if zb_rx.body.zcl_body.move_mode.value == LevelControl.types.MoveStepMode.UP then
    device:set_field(VIMAR_HOLD_BUTTON, "button1")
    emit_button_event("button1", device, capabilities.button.button.down_hold({state_change = true}))
  elseif zb_rx.body.zcl_body.move_mode.value == LevelControl.types.MoveStepMode.DOWN then
    device:set_field(VIMAR_HOLD_BUTTON, "button2")
    emit_button_event("button2", device, capabilities.button.button.down_hold({state_change = true}))
  else
    log.warn("MoveStepMode value not supported")
  end
end

local function vimar_release_button_hold(driver, device, zb_rx)
  local hold_button = device:get_field(VIMAR_HOLD_BUTTON)
  emit_button_event(hold_button, device, capabilities.button.button.up({state_change = true}))
end

local do_configure = function(self, device)
  device:send(device_management.build_bind_request(device, OnOff.ID, self.environment_info.hub_zigbee_eui))
  device:send(device_management.build_bind_request(device, LevelControl.ID, self.environment_info.hub_zigbee_eui))
  for _, component in pairs(device.profile.components) do
    local number_of_buttons = component.id == "main" and 2 or 1
    device:emit_component_event(component,
      capabilities.button.supportedButtonValues({ "pushed", "down_hold", "up" }, { visibility = { displayed = true } }))
    device:emit_component_event(component,
      capabilities.button.numberOfButtons({ value = number_of_buttons }, { visibility = { displayed = true } }))
  end
end

local vimar_remote_control = {
  NAME = "Vimar Remote Control",
  zigbee_handlers = {
    cluster = {
      [OnOff.ID] = {
        [OnOff.server.commands.Off.ID] = vimar_down_button_pushed,
        [OnOff.server.commands.On.ID] = vimar_up_button_pushed
      },
      [LevelControl.ID] = {
        [LevelControl.server.commands.Move.ID] = vimar_button_hold,
        [LevelControl.server.commands.Stop.ID] = vimar_release_button_hold
      }
    }
  },
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  can_handle = require("zigbee-multi-button.vimar.can_handle"),
}

return vimar_remote_control
