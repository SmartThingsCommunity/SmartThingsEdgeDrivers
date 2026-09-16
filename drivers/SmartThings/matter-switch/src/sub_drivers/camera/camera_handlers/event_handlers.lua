-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local camera_fields = require "sub_drivers.camera.camera_utils.fields"
local capabilities = require "st.capabilities"

local CameraEventHandlers = {}

local function has_triggered_zone(triggered_zones, zone_id)
  for _, zone in ipairs(triggered_zones or {}) do
    if zone.zoneId == zone_id then
      return true
    end
  end
  return false
end

function CameraEventHandlers.zone_triggered_handler(driver, device, ib, response)
  local triggered_zones = device:get_field(camera_fields.TRIGGERED_ZONES) or {}
  local zone_id = ib.data.elements.zone.value
  if not has_triggered_zone(triggered_zones, zone_id) then
    table.insert(triggered_zones, { zoneId = zone_id })
    device:set_field(camera_fields.TRIGGERED_ZONES, triggered_zones)
    device:emit_event_for_endpoint(ib, capabilities.zoneManagement.triggeredZones(triggered_zones))
  end
end

function CameraEventHandlers.zone_stopped_handler(driver, device, ib, response)
  local triggered_zones = device:get_field(camera_fields.TRIGGERED_ZONES) or {}
  local zone_id = ib.data.elements.zone.value
  local updated_triggered_zones = {}
  local zone_removed = false

  for _, zone in ipairs(triggered_zones) do
    if zone.zoneId ~= zone_id then
      table.insert(updated_triggered_zones, zone)
    else
      zone_removed = true
    end
  end

  if zone_removed then
    device:set_field(camera_fields.TRIGGERED_ZONES, updated_triggered_zones)
    device:emit_event_for_endpoint(ib, capabilities.zoneManagement.triggeredZones(updated_triggered_zones))
  end
end

return CameraEventHandlers
