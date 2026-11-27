-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
--- @type st.zwave.defaults
local defaults = require "st.zwave.defaults"
--- @type st.zwave.Driver
local ZwaveDriver = require "st.zwave.driver"

--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=4 })

local preferencesMap = require "preferences"

--- Handle preference changes
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @param event table
--- @param args
local function info_changed(driver, device, event, args)
  local preferences = preferencesMap.get_device_parameters(device)
  if preferences then
    for id, value in pairs(device.preferences) do
      if preferences[id] and args.old_st_store.preferences[id] ~= value then
        local new_parameter_value = preferencesMap.to_numeric_value(device.preferences[id])
        --2's complement value if needed
        --fix for Configuration:Set() not yet packing unsigned bytes > 127  correctly
        if preferences[id].size == 1 and new_parameter_value > 127 then
          new_parameter_value = new_parameter_value - 256
        end
        device:send(Configuration:Set({parameter_number = preferences[id].parameter_number, size = preferences[id].size, configuration_value = new_parameter_value}))
      end
    end
  end
end

--------------------------------------------------------------------------------------------
-- Register message handlers and run driver
--------------------------------------------------------------------------------------------

local driver_template = {
  supported_capabilities = {
    capabilities.switch,
    capabilities.fanSpeed,
    capabilities.switchLevel,
  },
  lifecycle_handlers = {
    infoChanged = info_changed
  },
  sub_drivers = require("sub_drivers"),
  shared_device_thread_enabled = true,
}

defaults.register_for_default_handlers(driver_template, driver_template.supported_capabilities)
--- @type st.zwave.Driver
local fan = ZwaveDriver("zwave_fan", driver_template)
fan:run()
