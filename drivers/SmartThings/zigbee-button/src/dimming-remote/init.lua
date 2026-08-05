-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local zcl_clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local Level = zcl_clusters.Level
local OnOff = zcl_clusters.OnOff
local PowerConfiguration = zcl_clusters.PowerConfiguration
local device_management = require "st.zigbee.device_management"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"

local button_utils = require "button_utils"



local function button_pushed_handler(button_number)
  return function(self, device, value, zb_rx)
    button_utils.init_button_press(device, button_number)
  end
end

local function button_released_handler(self, device, value, zb_rx)
  button_utils.send_pushed_or_held_button_event_if_applicable(device, 1)
  button_utils.send_pushed_or_held_button_event_if_applicable(device, 2)
end

local function added_handler(self, device)
  for _, component in pairs(device.profile.components) do
    local number_of_buttons = component.id == "main" and 2 or 1
    device:emit_component_event(component, capabilities.button.supportedButtonValues({"pushed", "held"}, {visibility = { displayed = false }}))
    device:emit_component_event(component, capabilities.button.numberOfButtons({value = number_of_buttons}, {visibility = { displayed = false }}))
  end
  device:send(PowerConfiguration.attributes.BatteryVoltage:read(device))
  button_utils.emit_event_if_latest_state_missing(device, "main", capabilities.button, capabilities.button.button.NAME, capabilities.button.button.pushed({state_change = false}))
end

local function do_configure(self, device)
  device:send(PowerConfiguration.attributes.BatteryVoltage:configure_reporting(device, 30, 21600, 1))
  device:send(device_management.build_bind_request(device, OnOff.ID, self.environment_info.hub_zigbee_eui))
  device:send(device_management.build_bind_request(device, Level.ID, self.environment_info.hub_zigbee_eui))
  device:send(device_management.build_bind_request(device, PowerConfiguration.ID, self.environment_info.hub_zigbee_eui))
end

local dimming_remote = {
  NAME = "Dimming Remote",
  lifecycle_handlers = {
    init = battery_defaults.build_linear_voltage_init(2.1, 3.0),
    added = added_handler,
    doConfigure = do_configure
  },
  zigbee_handlers = {
    cluster = {
      [Level.ID] = {
        [Level.server.commands.Move.ID] = button_pushed_handler(2),
        [Level.server.commands.MoveWithOnOff.ID] = button_pushed_handler(1),
        [Level.server.commands.Stop.ID] = button_released_handler
      },
      [OnOff.ID] = {
        [OnOff.server.commands.Off.ID] = button_utils.build_button_handler("button2", capabilities.button.button.pushed),
        [OnOff.server.commands.On.ID] = button_utils.build_button_handler("button1", capabilities.button.button.pushed)
      }
    }
  },
  can_handle = require("dimming-remote.can_handle"),
}

return dimming_remote
