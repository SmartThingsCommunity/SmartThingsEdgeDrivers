-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local IASZone = clusters.IASZone

local function generate_event_from_zone_status(driver, device, zone_status, zb_rx)
  device:emit_event(zone_status:is_alarm1_set() and capabilities.contactSensor.contact.open() or capabilities.contactSensor.contact.closed())
  if device:supports_capability_by_id(capabilities.tamperAlert.ID) then
    device:emit_event(zone_status:is_tamper_set() and capabilities.tamperAlert.tamper.detected() or capabilities.tamperAlert.tamper.clear())
  end
end

local function ias_zone_status_attr_handler(driver, device, attr_val, zb_rx)
  generate_event_from_zone_status(driver, device, attr_val, zb_rx)
end

local function ias_zone_status_change_handler(driver, device, zb_rx)
  generate_event_from_zone_status(driver, device, zb_rx.body.zcl_body.zone_status, zb_rx)
end

local function added_handler(driver, device)
  device:emit_event(capabilities.battery.battery(100))
  device:emit_event(capabilities.contactSensor.contact.closed())
  if device:supports_capability_by_id(capabilities.tamperAlert.ID) then
    device:emit_event(capabilities.tamperAlert.tamper.clear())
  end
end

local MultiIR_sensor = {
  NAME = "MultiIR Contact Sensor",
  lifecycle_handlers = {
    added = added_handler
  },
  zigbee_handlers = {
    cluster = {
      [IASZone.ID] = {
        [IASZone.client.commands.ZoneStatusChangeNotification.ID] = ias_zone_status_change_handler,
      }
    },
    attr = {
      [IASZone.ID] = {
        [IASZone.attributes.ZoneStatus.ID] = ias_zone_status_attr_handler,
      }
    }
  },
  can_handle = require("MultiIR.can_handle")
}

return MultiIR_sensor
