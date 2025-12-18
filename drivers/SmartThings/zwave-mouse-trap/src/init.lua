-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
--- @type st.zwave.defaults
local defaults = require "st.zwave.defaults"
--- @type st.zwave.Driver
local ZwaveDriver = require "st.zwave.driver"
--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 4 })
--- @type st.zwave.CommandClass.Notification
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })
--- @type st.zwave.CommandClass.WakeUp
local WakeUp = (require "st.zwave.CommandClass.WakeUp")({ version = 1 })


--------------------------------------------------------------------------------------------
-- Register message handlers and run driver
--------------------------------------------------------------------------------------------

local do_configure = function(self, device)
  device:refresh()
  device:send(Notification:Get({ notification_type = Notification.notification_type.PEST_CONTROL}))
  device:send(WakeUp:IntervalSet({node_id = self.environment_info.hub_zwave_id, seconds = 43200}))
  --// BASIC_SET Level, default: 255
  device:send(Configuration:Set({ parameter_number=1,  configuration_value= 255, size=2}))
  --// Set Firing Mode, default: 2 (Burst fire)
  device:send(Configuration:Set({ parameter_number=2,  configuration_value= 2, size=1}))
  --// This parameter defines how long the Mouser will fire continuously before it starts to burst-fire, default: 360 seconds
  device:send(Configuration:Set({ parameter_number=3,  configuration_value= 360, size=2}))
  --// Enable/Disable LED Alarm, default: 1 (enabled)
  device:send(Configuration:Set({ parameter_number=4,  configuration_value= 1, size=1}))
  --// LED Alarm Duration, default: 0 hours
  device:send(Configuration:Set({ parameter_number=5,  configuration_value= 0, size=1}))
end

local driver_template = {
  supported_capabilities = {
    capabilities.pestControl,
    capabilities.battery,
  },
  lifecycle_handlers = {
    doConfigure = do_configure
  },
}

defaults.register_for_default_handlers(driver_template, driver_template.supported_capabilities)
--- @type st.zwave.Driver
local mouse_trap = ZwaveDriver("zwave_mouse_trap", driver_template)
mouse_trap:run()
