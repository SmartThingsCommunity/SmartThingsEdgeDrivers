-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local OnOff = zcl_clusters.OnOff
local PowerConfiguration = zcl_clusters.PowerConfiguration
local utils = require "st.utils"

-- Battery Polling Interval (seconds): SWV1C is a battery sleep device, polling every 2 hours
local BATTERY_POLL_INTERVAL = 7200

--- OnOff Property Reporting Handler → Valve Capability Point Event
--- It must be handled explicitly because the child driver defines capability_handlers.
--- The default OnOff→valve mapping from the parent driver will be skipped (only OnOff→switch remains)
--- @param driver table Driver instance
--- @param device table Device instance
--- @param value table Zigbee attribute value
local function onoff_attr_handler(driver, device, value)
  local is_on = value.value ~= false and value.value ~= 0
  if is_on then
    device:emit_event(capabilities.valve.valve.open())
  else
    device:emit_event(capabilities.valve.valve.closed())
  end
end

--- Battery Percentage Attribute Handler
--- Zigbee BatteryPercentageRemaining range 0-200 (0%-100%), needs to be divided by 2
--- @param driver table Driver instance
--- @param device table Device instance
--- @param value table Zigbee attribute value
local function battery_percentage_handler(driver, device, value)
  local raw = value.value
  local percent = utils.round(raw / 2)
  device:emit_event(capabilities.battery.battery(percent))
end

--- Lifecycle initialization handler
--- Ensures battery data is available by periodically actively reading BatteryPercentageRemaining
--- @param driver table Driver instance
--- @param device table Device instance
local function device_init(driver, device)
  device.thread:call_on_schedule(
    BATTERY_POLL_INTERVAL,
    function()
      device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:read(device))
    end
  )
end

--- valve.open ability handler
--- @param driver table driver instance
--- @param device table device instance
--- @param command table ability command
local function valve_open_handler(driver, device, command)
  device:send(OnOff.server.commands.On(device))
  device:send(OnOff.attributes.OnOff:read(device))
end

--- valve.close capability handler
--- @param driver table driver instance
--- @param device table device instance
--- @param command table capability command
local function valve_close_handler(driver, device, command)
  device:send(OnOff.server.commands.Off(device))
  device:send(OnOff.attributes.OnOff:read(device))
end

local sonoff_valve_handler = {
  NAME = "SONOFF Water Valve Handler",
  lifecycle_handlers = {
    init = device_init
  },
  capability_handlers = {
    [capabilities.valve.ID] = {
      [capabilities.valve.commands.open.NAME] = valve_open_handler,
      [capabilities.valve.commands.close.NAME] = valve_close_handler,
    }
  },
  zigbee_handlers = {
    attr = {
      -- OnOff property reporting → valve event (to compensate for the defect of the parent driver's default mapping being skipped)
      [OnOff.ID] = {
        [OnOff.attributes.OnOff.ID] = onoff_attr_handler
      },
      -- Battery percentage attribute reporting → battery event
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryPercentageRemaining.ID] = battery_percentage_handler
      }
    }
  },
  can_handle = require "sonoff.can_handle",
}

return sonoff_valve_handler
