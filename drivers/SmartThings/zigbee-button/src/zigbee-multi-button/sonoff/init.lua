-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"

local SONOFF_CLUSTER_ID = 0xFC12
local SONOFF_ATTR_ID = 0x0000

local EVENT_MAP = {
  [0x01] = capabilities.button.button.pushed,
  [0x02] = capabilities.button.button.double,
  [0x03] = capabilities.button.button.held,
  [0x04] = capabilities.button.button.pushed_3x
}

local function sonoff_attr_handler(driver, device, value, zb_rx)
  local attr_val = value.value
  local endpoint = zb_rx.address_header.src_endpoint.value
  local button_name = "button" .. tostring(endpoint)
  local event_func = EVENT_MAP[attr_val]
  if event_func then
    local comp = device.profile.components[button_name]
    if comp then
        device:emit_component_event(comp, event_func({state_change = true}))
    end
  end
end

local sonoff_handler = {
  NAME = "SONOFF Multi-Button Handler",
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
