-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local log = require "log"
local lua_socket = require "socket"

local button_utils = {}

local BUTTON_X_PRESS_TIME = "button_%d_pressed_time"
local TIMEOUT_THRESHOLD = 10

button_utils.init_button_press = function(device, button_number)
  device:set_field(string.format(BUTTON_X_PRESS_TIME, button_number or 0), lua_socket.gettime())
end

button_utils.send_pushed_or_held_button_event_if_applicable = function(device, button_number)
  local press_time = device:get_field(string.format(BUTTON_X_PRESS_TIME, button_number or 0))
  local hold_time_threshold = tonumber(device.preferences.holdTime or 1)

  if press_time == nil then
    press_time = device:get_field(string.format(BUTTON_X_PRESS_TIME, 0))
    if press_time == nil then
      return
    end
    device:set_field(string.format(BUTTON_X_PRESS_TIME, 0), nil)
  end
  device:set_field(string.format(BUTTON_X_PRESS_TIME, button_number or 0), nil)
  local additional_fields = {state_change = true}
  local time_diff = lua_socket.gettime() - press_time
  local button_name
  if button_number ~= nil then
    button_name = "button" .. button_number
  else
    button_name = "main"
  end
  if time_diff < TIMEOUT_THRESHOLD  then
    local event = time_diff < hold_time_threshold and
      capabilities.button.button.pushed(additional_fields) or
      capabilities.button.button.held(additional_fields)
    local component = device.profile.components[button_name]
    if component ~= nil then
      device:emit_component_event(component, event)
      if button_name ~= "main" then
        device:emit_event(event)
      end
    else
      log.warn("Attempted to emit button event for non-existing component: " .. button_name)
    end
  end
end

button_utils.build_button_handler = function(button_name, pressed_type)
  return function(driver, device, zb_rx)
    local additional_fields = {
      state_change = true
    }
    local event = pressed_type(additional_fields)
    local comp = device.profile.components[button_name]
    if comp ~= nil then
      device:emit_component_event(comp, event)
      if button_name ~= "main" then
        device:emit_event(event)
      end
    else
      log.warn("Attempted to emit button event for unknown button: " .. button_name)
    end
  end
end

button_utils.emit_event_if_latest_state_missing = function(device, component, capability, attribute_name, value)
  if device:get_latest_state(component, capability.ID, attribute_name) == nil then
    device:emit_event(value)
  end
end

return button_utils
