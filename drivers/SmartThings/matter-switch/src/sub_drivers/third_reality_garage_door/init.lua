-- Copyright © 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"

-------------------------------------------------------------------------------------
-- Third Reality Garage Door Opener specifics
--
-- This device uses the OnOff cluster to control the door:
--   OnOff = true  -> door open
--   OnOff = false -> door closed
-- Commands are mapped from doorControl capability to OnOff cluster commands.
-------------------------------------------------------------------------------------

local function device_init(driver, device)
  -- Force a subscription to the OnOff cluster, since doorControl does not explicitly map to it in the default driver.
  device:add_subscribed_attribute(clusters.OnOff.attributes.OnOff)
  device:add_subscribed_attribute(clusters.PowerSource.attributes.BatPercentRemaining)
  device:subscribe()
end

local function match_profile(driver, device)
  device:try_update_metadata({profile = "garage-door-battery"})
end

-- Prevent any of the main driver's logic from running
local function device_added(driver, device) end

-- Prevent any of the main driver's logic from running
local function info_changed(driver, device, event, args) end

local function do_configure(driver, device)
  match_profile(driver, device)
end

local function driver_switched(driver, device)
  match_profile(driver, device)
end


local function on_off_attr_handler(driver, device, ib, response)
  if ib.data.value then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.doorControl.door.open())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.doorControl.door.closed())
  end
end

local function handle_door_open(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:emit_event_for_endpoint(endpoint_id, capabilities.doorControl.door.opening())
  device:send(clusters.OnOff.server.commands.On(device, endpoint_id))
end

local function handle_door_close(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:emit_event_for_endpoint(endpoint_id, capabilities.doorControl.door.closing())
  device:send(clusters.OnOff.server.commands.Off(device, endpoint_id))
end

local third_reality_garage_door_handler = {
  NAME = "ThirdReality Garage Door Handler",
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    doConfigure = do_configure,
    driverSwitched = driver_switched,
    infoChanged = info_changed,
  },
  matter_handlers = {
    attr = {
      [clusters.OnOff.ID] = {
        [clusters.OnOff.attributes.OnOff.ID] = on_off_attr_handler,
      },
    },
  },
  capability_handlers = {
    [capabilities.doorControl.ID] = {
      [capabilities.doorControl.commands.open.NAME] = handle_door_open,
      [capabilities.doorControl.commands.close.NAME] = handle_door_close,
    },
  },
  supported_capabilities = {
    capabilities.doorControl,
    capabilities.battery,
  },
  can_handle = require("sub_drivers.third_reality_garage_door.can_handle")
}

return third_reality_garage_door_handler
