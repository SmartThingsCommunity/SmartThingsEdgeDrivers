-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local clusters = require "st.matter.clusters"
local st_utils = require "st.utils"
local version = require "version"

local PROFILE = "thingsone-presence-sensor"

local settings = {
  {
    -- Not the attribute's standard use, kept on purpose: the certified device firmware reads it as its operation
    -- mode: 1 low power, 2 normal, 3 high power
    attr = clusters.OccupancySensing.attributes.PIRUnoccupiedToOccupiedThreshold,
    pref = "stse.sensitivity",
    min = 1, max = 3,
  },
}
-- HoldTime comes with lua libs api 13 (OccupancySensing revision 5); on older libs even looking it up raises an error
if version.api >= 13 then
  table.insert(settings, {
    -- HoldTime is the device's shipped 20 s (a 10 s rest after motion, then 10 s of radar check that each radar detection restarts) plus the presence hold time; max keeps it within HoldTimeLimits 1..300
    attr = clusters.OccupancySensing.attributes.HoldTime,
    pref = "stse.presenceHoldTime",
    min = 0, max = 280,
    to_device = function(seconds) return 20 + seconds end,
  })
end

local function write_setting(device, setting, preference)
  local value = tonumber(preference)
  local ep = device:get_endpoints(clusters.OccupancySensing.ID)[1]
  if value == nil or ep == nil then
    return
  end
  value = st_utils.clamp_value(math.floor(value), setting.min, setting.max)
  device:send(setting.attr:write(device, ep, setting.to_device and setting.to_device(value) or value))
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
  if version.api < 13 then
    device.log.warn("OccupancySensing.HoldTime needs lua libs api 13; the presence hold time setting has no effect")
  end
  device:subscribe()
end

function ThingsOneLifecycleHandlers.info_changed(driver, device, event, args)
  if device.profile.id ~= args.old_st_store.profile.id then
    device:subscribe()
  end
  local old = args.old_st_store.preferences or {}
  local new = device.preferences or {}
  for _, setting in ipairs(settings) do
    if new[setting.pref] ~= nil and new[setting.pref] ~= old[setting.pref] then
      write_setting(device, setting, new[setting.pref])
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
  can_handle = require("sub_drivers.thingsone_presence_sensor.can_handle"),
}

return thingsone_presence_sensor_handler
