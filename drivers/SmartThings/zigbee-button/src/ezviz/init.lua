-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"

local EZVIZ_PRIVATE_BUTTON_CLUSTER = 0xFE05
local EZVIZ_PRIVATE_BUTTON_ATTRIBUTE = 0x0000


local ezviz_private_cluster_button_handler = function(driver, device, zb_rx)
  local event
  local additional_fields = {
    state_change = true
  }
  if zb_rx.value == 0x01 then
    event = capabilities.button.button.pushed(additional_fields)
  elseif zb_rx.value == 0x02 then
    event = capabilities.button.button.double(additional_fields)
  elseif zb_rx.value == 0x03 then
    event = capabilities.button.button.held(additional_fields)
  end
  if event ~= nil then
    device:emit_event(event)
  end
end

local ezviz_button_handler = {
  NAME = "Ezviz Button",
  zigbee_handlers = {
    attr = {
      [EZVIZ_PRIVATE_BUTTON_CLUSTER] = {
        [EZVIZ_PRIVATE_BUTTON_ATTRIBUTE] = ezviz_private_cluster_button_handler
      }
    }
  },
  can_handle = require("ezviz.can_handle"),
}
return ezviz_button_handler
