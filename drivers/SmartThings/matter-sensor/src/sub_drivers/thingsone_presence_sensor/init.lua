-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local clusters = require "st.matter.clusters"
local st_utils = require "st.utils"
local version = require "version"

local PROFILE = "thingsone-presence-sensor"
local PRESENCE_HOLD_TIME = "stse.presenceHoldTime"

-- HoldTime is the device's shipped 20 s (a 10 s rest after motion, then 10 s of radar check that each radar detection restarts) plus the presence hold time; 280 keeps it within HoldTimeLimits 1..300
local function write_presence_hold_time(device, preference)
  local seconds = tonumber(preference)
  local ep = device:get_endpoints(clusters.OccupancySensing.ID)[1]
  if seconds == nil or ep == nil then
    return
  end
  seconds = st_utils.clamp_value(math.floor(seconds), 0, 280)
  device:send(clusters.OccupancySensing.attributes.HoldTime:write(device, ep, 20 + seconds))
end

local ThingsOneLifecycleHandlers = {}

-- Keeps the base driver from re-matching the device to a profile without the presence hold time setting
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
  -- HoldTime comes with lua libs api 13 (OccupancySensing revision 5); on older libs even looking it up raises an error
  if version.api >= 13 and new[PRESENCE_HOLD_TIME] ~= nil and new[PRESENCE_HOLD_TIME] ~= old[PRESENCE_HOLD_TIME] then
    write_presence_hold_time(device, new[PRESENCE_HOLD_TIME])
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
