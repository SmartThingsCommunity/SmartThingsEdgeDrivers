-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local IASZone = zcl_clusters.IASZone

local generate_event_from_zone_status = function(driver, device, zone_status, zigbee_message)
  local result_occupied = 0x8000
  local result_open = 0x4000
  local result_close = 0x2000
  local result_battery_new = 0x1000
  local result_battery_low = 0x0800
  if zone_status:is_alarm1_set() then
    device:emit_event(capabilities.motionSensor.motion.active())
    -- emit inactive after 2 minutes
    device.thread:call_with_delay(120, function(d)
      device:emit_event(capabilities.motionSensor.motion.inactive())
    end
    )
  elseif zone_status:is_battery_low_set() then
    device:emit_event(capabilities.battery.battery(10))
  elseif zone_status.value == result_occupied then
    device:emit_event(capabilities.presenceSensor.presence.present())
    -- emit inactive after 1 minute
    device.thread:call_with_delay(60, function(d)
      device:emit_event(capabilities.presenceSensor.presence.not_present())
    end
    )
  elseif zone_status.value == result_open or zone_status.value == result_close then
    device:emit_event(zone_status.value == result_open and capabilities.contactSensor.contact.open() or capabilities.contactSensor.contact.closed())
  elseif zone_status.value == result_battery_new then
    device:emit_event(capabilities.battery.battery(100))
  elseif zone_status.value == result_battery_low then
    device:emit_event(capabilities.battery.battery(0))
  end
end

local function ias_zone_status_attr_handler(driver, device, zone_status, zb_rx)
  generate_event_from_zone_status(driver, device, zone_status, zb_rx)
end

local function ias_zone_status_change_handler(driver, device, zb_rx)
  generate_event_from_zone_status(driver, device, zb_rx.body.zcl_body.zone_status, zb_rx)
end

local device_added = function(self, device)
  device:emit_event(capabilities.motionSensor.motion.inactive())
  device:emit_event(capabilities.contactSensor.contact.closed())
  device:emit_event(capabilities.presenceSensor.presence.not_present())
  device:emit_event(capabilities.battery.battery(100))
end

local do_configure = function(self, device)
  -- Override default as none of attribute requires to be configured
end

local gator_handler = {
  NAME = "GatorSystem Handler",
  zigbee_handlers = {
    cluster = {
      [IASZone.ID] = {
        [IASZone.client.commands.ZoneStatusChangeNotification.ID] = ias_zone_status_change_handler
      }
    },
    attr = {
      [IASZone.ID] = {
        [IASZone.attributes.ZoneStatus.ID] = ias_zone_status_attr_handler
      }
    }
  },
  lifecycle_handlers = {
    added = device_added,
    doConfigure = do_configure
  },
  can_handle = require("gatorsystem.can_handle"),
}

return gator_handler
