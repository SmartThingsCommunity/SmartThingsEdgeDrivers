-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local button_utils = require "button_utils"

local SONOFF_CLUSTER_ID = 0xFC12
local SONOFF_ATTR_ID = 0x0000
local SONOFF_SUPPORTED_BUTTON_VALUES = { "pushed", "double", "held", "pushed_3x" }
local SONOFF_NUMBER_OF_BUTTONS = 4

local EVENT_MAP = {
  [0x01] = capabilities.button.button.pushed,
  [0x02] = capabilities.button.button.double,
  [0x03] = capabilities.button.button.held,
  [0x04] = capabilities.button.button.pushed_3x
}

local function added_handler(self, device)
  for _, component in pairs(device.profile.components) do
    local number_of_buttons = component.id == "main" and SONOFF_NUMBER_OF_BUTTONS or 1
    device:emit_component_event(component,
      capabilities.button.supportedButtonValues(SONOFF_SUPPORTED_BUTTON_VALUES, { visibility = { displayed = false } }))
    device:emit_component_event(component,
      capabilities.button.numberOfButtons({ value = number_of_buttons }, { visibility = { displayed = false } }))
  end

  button_utils.emit_event_if_latest_state_missing(device, "main", capabilities.button,
    capabilities.button.button.NAME, capabilities.button.button.pushed({ state_change = false }))
end

local function sonoff_attr_handler(driver, device, value, zb_rx)
  local attr_val = value.value
  local endpoint = zb_rx.address_header.src_endpoint.value
  local button_name = "button" .. tostring(endpoint)
  local event_func = EVENT_MAP[attr_val]
  if event_func then
    local comp = device.profile.components[button_name]
    if comp then
      local event = event_func({ state_change = true })
      device:emit_component_event(comp, event)
      device:emit_event(event)
    end
  end
end

local sonoff_handler = {
  NAME = "SONOFF Multi-Button Handler",
  lifecycle_handlers = {
    added = added_handler
  },
  zigbee_handlers = {
    attr = {
      [SONOFF_CLUSTER_ID] = {
        [SONOFF_ATTR_ID] = sonoff_attr_handler
      }
    }
  },
  can_handle = require("zigbee-multi-button.sonoff.can_handle")
}

return sonoff_handler
