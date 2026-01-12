-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Basic
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })
--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 1 })

local SHADE_STATE_OPENING = "opening"
local SHADE_STATE_CLOSING = "closing"
local SHADE_STATE_PAUSED = "paused"
local SET_BUTTON_TO_OPEN = "open"
local SET_BUTTON_TO_CLOSE = "close"
local SET_BUTTON_TO_PAUSE = "pause"
local SHADE_STATE = "shade_state"


--- Determine whether the passed device is proper
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @return boolean true if the device is proper, else false

--- Default handler for basic reports for the devices
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @param cmd st.zwave.CommandClass.Basic.Report
local function basic_report_handler(driver, device, cmd)
  local state
  if device.preferences.reverse then
    state = cmd.args.value == 0x00 and SHADE_STATE_CLOSING or SHADE_STATE_OPENING
  else
    state = cmd.args.value == 0xFF and SHADE_STATE_CLOSING or SHADE_STATE_OPENING
  end
  device:set_field(SHADE_STATE, state)
end

local capability_handlers = {}

--- Issue a stateless curtain power button set button command to the device.
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @param cmd table ST level capability command
function capability_handlers.set_button(driver, device, cmd)
  local value
  local state
  local close_value = device.preferences.reverse and 0x00 or 0xFF
  local open_value = device.preferences.reverse and 0xFF or 0x00
  local button = cmd.positional_args[1]
  if button == SET_BUTTON_TO_OPEN then
    value = open_value
    state = SHADE_STATE_OPENING
  elseif button == SET_BUTTON_TO_CLOSE then
    value = close_value
    state = SHADE_STATE_CLOSING
  elseif button == SET_BUTTON_TO_PAUSE then
    value = device:get_field(SHADE_STATE) == SHADE_STATE_CLOSING and close_value or open_value
    state = SHADE_STATE_PAUSED
  end
  device:set_field(SHADE_STATE, state)
  device:send(Basic:Set({ value = value }))
end

--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
local function added_handler(driver, device)
  device:emit_event(capabilities.statelessCurtainPowerButton.availableCurtainPowerButtons(
    {SET_BUTTON_TO_OPEN, SET_BUTTON_TO_CLOSE, SET_BUTTON_TO_PAUSE},
    {visibility = {displayed = false}})
  )
end

--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
local function refresh(driver, device)
  -- if we've already got an added device that hasn't set this value, this should cause it to be set on refresh
  -- this can be removed later
  if device:get_latest_state(
    "main",
    capabilities.statelessCurtainPowerButton.ID,
    capabilities.statelessCurtainPowerButton.availableCurtainPowerButtons.NAME) == nil then
    added_handler(driver, device)
  end
  device:send(Basic:Get({}))
end

--- @param self st.zwave.Driver
--- @param device st.zwave.Device
local function do_configure(driver, device)
  device:send(Configuration:Set({parameter_number = 80, size = 1, configuration_value = 1}))
  device:send(Configuration:Set({parameter_number = 85, size = 1, configuration_value = 1}))
end

local aeotec_nano_shutter = {
  zwave_handlers = {
    [cc.BASIC] = {
        [Basic.REPORT] = basic_report_handler
    }
  },
  capability_handlers = {
    [capabilities.statelessCurtainPowerButton.ID] = {
      [capabilities.statelessCurtainPowerButton.commands.setButton.NAME] = capability_handlers.set_button
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = refresh
    }
  },
  lifecycle_handlers = {
    doConfigure = do_configure,
    added = added_handler
  },
  NAME = "Aeotec nano shutter",
  can_handle = require("aeotec-nano-shutter.can_handle"),
}

return aeotec_nano_shutter
