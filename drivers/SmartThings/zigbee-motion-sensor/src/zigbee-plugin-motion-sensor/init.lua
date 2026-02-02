-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local device_management = require "st.zigbee.device_management"
local OccupancySensing = zcl_clusters.OccupancySensing



local function occupancy_attr_handler(driver, device, occupancy, zb_rx)
  device:emit_event(occupancy.value == 0x01 and capabilities.motionSensor.motion.active() or capabilities.motionSensor.motion.inactive())
end

local do_configure = function(self, device)
  device:send(device_management.build_bind_request(device, OccupancySensing.ID, self.environment_info.hub_zigbee_eui))
end

local do_refresh = function(self, device)
  device:send(OccupancySensing.attributes.Occupancy:read(device))
end

local zigbee_plugin_motion_sensor = {
  NAME = "zigbee plugin motion sensor",
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  zigbee_handlers = {
    attr = {
      [OccupancySensing.ID] = {
        [OccupancySensing.attributes.Occupancy.ID] = occupancy_attr_handler
      }
    }
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    }
  },
  can_handle = require("zigbee-plugin-motion-sensor.can_handle"),
}

return zigbee_plugin_motion_sensor
