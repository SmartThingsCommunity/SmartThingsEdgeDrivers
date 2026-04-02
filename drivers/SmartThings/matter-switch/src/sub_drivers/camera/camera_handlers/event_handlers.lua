-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local camera_fields = require "sub_drivers.camera.camera_utils.fields"
local capabilities = require "st.capabilities"
local switch_utils = require "switch_utils.utils"

local CameraEventHandlers = {}

function CameraEventHandlers.zone_triggered_handler(driver, device, ib, response)
  local triggered_zones = device:get_field(camera_fields.TRIGGERED_ZONES) or {}
  if not switch_utils.tbl_contains(triggered_zones, ib.data.elements.zone.value) then
    table.insert(triggered_zones, {zoneId = ib.data.elements.zone.value})
    device:set_field(camera_fields.TRIGGERED_ZONES, triggered_zones)
    device:emit_event_for_endpoint(ib, capabilities.zoneManagement.triggeredZones(triggered_zones))
  end
end

function CameraEventHandlers.zone_stopped_handler(driver, device, ib, response)
  local triggered_zones = device:get_field(camera_fields.TRIGGERED_ZONES) or {}
  for i, v in pairs(triggered_zones) do
    if v.zoneId == ib.data.elements.zone.value then
      table.remove(triggered_zones, i)
      device:set_field(camera_fields.TRIGGERED_ZONES, triggered_zones)
      device:emit_event_for_endpoint(ib, capabilities.zoneManagement.triggeredZones(triggered_zones))
    end
  end
end

return CameraEventHandlers
