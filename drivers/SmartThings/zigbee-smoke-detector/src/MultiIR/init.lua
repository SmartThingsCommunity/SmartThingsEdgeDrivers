-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local zcl_clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"

local IASZone = zcl_clusters.IASZone

local function generate_event_from_zone_status(driver, device, zone_status, zb_rx)
  if zone_status:is_alarm1_set() then
    device:emit_event(capabilities.smokeDetector.smoke.detected())
  elseif zone_status:is_alarm2_set() then
    device:emit_event(capabilities.smokeDetector.smoke.tested())
  else
    device:emit_event(capabilities.smokeDetector.smoke.clear())
  end
  if device:supports_capability(capabilities.tamperAlert) then
    device:emit_event(zone_status:is_tamper_set() and capabilities.tamperAlert.tamper.detected() or capabilities.tamperAlert.tamper.clear())
  end
end

local function ias_zone_status_change_handler(driver, device, zb_rx)
  local zone_status = zb_rx.body.zcl_body.zone_status
  generate_event_from_zone_status(driver, device, zone_status, zb_rx)
end

local function added_handler(self, device)
  device:emit_event(capabilities.battery.battery(100))
  device:emit_event(capabilities.smokeDetector.smoke.clear())
  device:emit_event(capabilities.tamperAlert.tamper.clear())
end

local MultiIR_smoke_detector_handler = {
  NAME = "MultiIR Smoke Detector Handler",
  lifecycle_handlers = {
    added = added_handler
  },
  zigbee_handlers = {
    cluster = {
      [IASZone.ID] = {
        [IASZone.client.commands.ZoneStatusChangeNotification.ID] = ias_zone_status_change_handler
      }
    },
    attr = {
      [IASZone.ID] = {
        [IASZone.attributes.ZoneStatus.ID] = generate_event_from_zone_status
      }
    }
  },
  can_handle = require("MultiIR.can_handle")
}

return MultiIR_smoke_detector_handler
