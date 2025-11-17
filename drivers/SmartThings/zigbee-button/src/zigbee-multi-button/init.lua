-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0



local capabilities = require "st.capabilities"
local supported_values = require "zigbee-multi-button.supported_values"
local button_utils = require "button_utils"



local function added_handler(self, device)
  local config = supported_values.get_device_parameters(device)
  for _, component in pairs(device.profile.components) do
    if config ~= nil then
      local number_of_buttons = component.id == "main" and config.NUMBER_OF_BUTTONS or 1
      device:emit_component_event(component,
        capabilities.button.supportedButtonValues(config.SUPPORTED_BUTTON_VALUES, { visibility = { displayed = false } }))
      device:emit_component_event(component,
        capabilities.button.numberOfButtons({ value = number_of_buttons }, { visibility = { displayed = false } }))
    else
      device:emit_component_event(component,
        capabilities.button.supportedButtonValues({ "pushed", "held" }, { visibility = { displayed = false } }))
      device:emit_component_event(component,
        capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false } }))
    end
  end
  button_utils.emit_event_if_latest_state_missing(device, "main", capabilities.button, capabilities.button.button.NAME, capabilities.button.button.pushed({state_change = false}))
end

local zigbee_multi_button = {
  NAME = "ZigBee multi button",
  lifecycle_handlers = {
    added = added_handler
  },
  can_handle = require("zigbee-multi-button.can_handle"),
  sub_drivers = require("zigbee-multi-button.sub_drivers"),
}

return zigbee_multi_button
