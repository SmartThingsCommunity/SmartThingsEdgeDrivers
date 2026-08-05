-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
--- @type st.zwave.constants
local constants = require "st.zwave.constants"
--- @type st.zwave.CommandClass.SwitchMultilevel
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({version=4})


--- Determine whether the passed device is springs window fashion shade
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @return boolean true if the device is springs window fashion shade, else false

local function init_handler(self, device)
  -- This device has a preset position set in hardware, so we need to override the base driver
  if device:supports_capability_by_id(capabilities.windowShadePreset.ID) and
    device:get_latest_state("main", capabilities.windowShadePreset.ID, capabilities.windowShadePreset.supportedCommands.NAME) == nil then

    -- setPresetPosition is not supported
    device:emit_event(capabilities.windowShadePreset.supportedCommands({"presetPosition"}, { visibility = { displayed = false }}))
  end
end

local capability_handlers = {}

--- Issue a window shade preset position command to the specified device.
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @param command table ST level capability command
function capability_handlers.preset_position(driver, device)
  local set = SwitchMultilevel:Set({
    value = SwitchMultilevel.value.ON_ENABLE,
    duration = constants.DEFAULT_DIMMING_DURATION
  })
  local get = SwitchMultilevel:Get({})
  device:send(set)
  local query_device = function()
    device:send(get)
  end
  device.thread:call_with_delay(constants.MIN_DIMMING_GET_STATUS_DELAY, query_device)
end

local springs_window_fashion_shade = {
  lifecycle_handlers = {
    init = init_handler
  },
  capability_handlers = {
    [capabilities.windowShadePreset.ID] = {
      [capabilities.windowShadePreset.commands.presetPosition.NAME] = capability_handlers.preset_position
    }
  },
  NAME = "Springs window fashion shade",
  can_handle = require("springs-window-fashion-shade.can_handle"),
}

return springs_window_fashion_shade
