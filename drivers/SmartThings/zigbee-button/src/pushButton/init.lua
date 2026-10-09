-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0



local capabilities = require "st.capabilities"
local button_utils = require "button_utils"

local function added_handler(self, device)
  device:emit_event(capabilities.button.supportedButtonValues({"pushed"}, {visibility = { displayed = false }}))
  device:emit_event(capabilities.button.numberOfButtons({value = 1}, {visibility = { displayed = false }}))
  button_utils.emit_event_if_latest_state_missing(device, "main", capabilities.button, capabilities.button.button.NAME, capabilities.button.button.pushed({state_change = false}))
end

local push_button = {
  NAME = "Non holdable Button",
  lifecycle_handlers = {
    added = added_handler,
  },
  sub_drivers = {},
  can_handle = require("pushButton.can_handle"),
}

return push_button
