-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local cc = require "st.zwave.CommandClass"
local Basic = (require "st.zwave.CommandClass.Basic")({version=1,strict=true})
local Battery = (require "st.zwave.CommandClass.Battery")({version=1})
local BatteryDefaults = require "st.zwave.defaults.battery"

local function device_added(self, device)
  device:send(Basic:Get({}))
  device:send(Battery:Get({}))
end

local function battery_report_handler(self, device, cmd)
  -- The Utilitech siren always sends low battery events (0xFF) below 20%,
	-- so we will ignore 0% events that sometimes seem to come before valid events.
  if cmd.args.battery_level ~= 0 then
    BatteryDefaults.zwave_handlers[cc.BATTERY][Battery.REPORT](self, device, cmd)
  end
end

local utilitech_siren = {
  NAME = "utilitech-siren",
  can_handle = require("utilitech-siren.can_handle"),
  zwave_handlers = {
    [cc.BATTERY] = {
      [Battery.REPORT] = battery_report_handler
    }
  },
  lifecycle_handlers = {
    added = device_added
  }
}

return utilitech_siren
