-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local PowerConfiguration = clusters.PowerConfiguration
local OnOff = clusters.OnOff
local device_management = require "st.zigbee.device_management"
local Groups = clusters.Groups



local function get_ep_num_shinasystem_button(device)
  local FINGERPRINTS = require("zigbee-multi-button.shinasystems.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_model() == fingerprint.model then
      return fingerprint.endpoint_num
    end
  end
end

local function build_button_handler(pressed_type)
  return function(driver, device, zb_rx)
    local additional_fields = {
      state_change = true
    }
    local event = pressed_type(additional_fields)
    local button_comp = string.format("button%d", zb_rx.address_header.src_endpoint.value)
    if device.profile.components[button_comp] == nil then
        button_comp = "main"
    end
    device:emit_component_event(device.profile.components[button_comp], event)
    if button_comp ~= "main" then
      device:emit_event(event)
    end
  end
end

local do_configure = function(self, device)
  device:configure()
  device:send(PowerConfiguration.attributes.BatteryVoltage:read(device))
  for endpoint = 1, get_ep_num_shinasystem_button(device) do
      device:send(device_management.build_bind_request(device, OnOff.ID, self.environment_info.hub_zigbee_eui, endpoint))
  end
  self:add_hub_to_zigbee_group(0x0000)
  device:send(Groups.commands.AddGroup(device, 0x0000))
end

local shinasystem_device_handler = {
  NAME = "ShinaSystem Device Handler",
  lifecycle_handlers = {
    init = battery_defaults.build_linear_voltage_init(2.1, 3.0),
    doConfigure = do_configure
  },
  zigbee_handlers = {
    cluster = {
      [OnOff.ID] = {
        [OnOff.server.commands.Off.ID] = build_button_handler(capabilities.button.button.pushed),
        [OnOff.server.commands.On.ID] = build_button_handler(capabilities.button.button.double),
        [OnOff.server.commands.Toggle.ID] = build_button_handler(capabilities.button.button.held)
      }
    }
  },
  can_handle = require("zigbee-multi-button.shinasystems.can_handle"),
}

return shinasystem_device_handler
