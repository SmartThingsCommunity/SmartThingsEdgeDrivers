-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local clusters = require "st.matter.clusters"
local st_utils = require "st.utils"

local PROFILE = "thingsone-presence-sensor"
local RETRY_LIMIT = 3
-- nil on hub libraries that predate this attribute
local HOLD_TIME_ATTR = clusters.OccupancySensing.attributes.HoldTime

local settings = {
  {
    -- The firmware reads this attribute as its operation mode: 1 low power, 2 normal, 3 high power
    attr = clusters.OccupancySensing.attributes.PIRUnoccupiedToOccupiedThreshold,
    pref = "stse.sensitivity",
    default = 2, min = 1, max = 3,
    pending = "__thingsone_mode_pending",
  },
}
if HOLD_TIME_ATTR ~= nil then
  table.insert(settings, {
    -- HoldTime is the device's shipped 20 s (a 10 s rest, then 10 s of radar check) plus the presence hold time; max keeps it within HoldTimeLimits 1..300
    attr = HOLD_TIME_ATTR,
    pref = "stse.presenceHoldTime",
    default = 0, min = 0, max = 280,
    to_device = function(seconds) return 20 + seconds end,
    pending = "__thingsone_hold_time_pending",
  })
end

-- An unset preference stands for the preference default, which setting.default must equal
local function preference_value(setting, preferences)
  local value = tonumber((preferences or {})[setting.pref]) or setting.default
  return st_utils.clamp_value(math.floor(value), setting.min, setting.max)
end

local function write_setting(device, setting, value, tries)
  local ep = device:get_endpoints(clusters.OccupancySensing.ID)[1]
  if ep == nil then
    return
  end
  device:set_field(setting.pending, {value = value, tries = tries})
  device:send(setting.attr:write(device, ep, value))
  device:send(setting.attr:read(device))
end

-- Only a write made here is checked and retried; values written by other controllers are left alone
local function setting_report_handler(setting)
  return function(driver, device, ib, response)
    local pending = device:get_field(setting.pending)
    if pending == nil or ib.data.value == nil then
      return
    end
    if ib.data.value == pending.value then
      device:set_field(setting.pending, nil)
    elseif pending.tries < RETRY_LIMIT then
      device.log.info(string.format("%s: device reports %d, rewriting %d (try %d)", setting.pref, ib.data.value, pending.value, pending.tries + 1))
      write_setting(device, setting, pending.value, pending.tries + 1)
    else
      device.log.warn(string.format("%s: device still reports %d, giving up on %d", setting.pref, ib.data.value, pending.value))
      device:set_field(setting.pending, nil)
    end
  end
end

local occupancy_attr_handlers = {}
for _, setting in ipairs(settings) do
  occupancy_attr_handlers[setting.attr.ID] = setting_report_handler(setting)
end

local ThingsOneLifecycleHandlers = {}

-- Keeps the base driver from re-matching the device to a profile without these settings
function ThingsOneLifecycleHandlers.do_configure(driver, device)
  device:try_update_metadata({profile = PROFILE})
end

function ThingsOneLifecycleHandlers.driver_switched(driver, device)
  device:try_update_metadata({profile = PROFILE})
  device:try_update_metadata({provisioning_state = "PROVISIONED"})
end

function ThingsOneLifecycleHandlers.device_init(driver, device)
  if HOLD_TIME_ATTR == nil then
    device.log.warn("OccupancySensing.HoldTime is missing from the hub libraries; the presence hold time setting has no effect")
  end
  for _, setting in ipairs(settings) do
    device:add_subscribed_attribute(setting.attr)
  end
  device:subscribe()
end

function ThingsOneLifecycleHandlers.info_changed(driver, device, event, args)
  if device.profile.id ~= args.old_st_store.profile.id then
    device:subscribe()
  end
  local old = args.old_st_store.preferences or {}
  local new = device.preferences or {}
  -- The platform adds the offset to emitted values, so re-read to show it before the next report
  if new.tempOffset ~= nil and new.tempOffset ~= old.tempOffset then
    device:send(clusters.TemperatureMeasurement.attributes.MeasuredValue:read(device))
  end
  if new.humidityOffset ~= nil and new.humidityOffset ~= old.humidityOffset then
    device:send(clusters.RelativeHumidityMeasurement.attributes.MeasuredValue:read(device))
  end
  for _, setting in ipairs(settings) do
    local value = preference_value(setting, new)
    if value ~= preference_value(setting, old) then
      write_setting(device, setting, setting.to_device and setting.to_device(value) or value, 0)
    end
  end
end

local thingsone_presence_sensor_handler = {
  NAME = "thingsone-presence-sensor",
  lifecycle_handlers = {
    doConfigure = ThingsOneLifecycleHandlers.do_configure,
    driverSwitched = ThingsOneLifecycleHandlers.driver_switched,
    infoChanged = ThingsOneLifecycleHandlers.info_changed,
    init = ThingsOneLifecycleHandlers.device_init,
  },
  matter_handlers = {
    attr = {
      [clusters.OccupancySensing.ID] = occupancy_attr_handlers,
    },
  },
  can_handle = require("sub_drivers.thingsone_presence_sensor.can_handle"),
}

return thingsone_presence_sensor_handler
