-- Copyright 2023 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local IASZone = zcl_clusters.IASZone

local generate_event_from_zone_status = function(driver, device, zone_status, zb_rx)
  local event
  if zone_status:is_alarm1_set() then
    event = capabilities.waterSensor.water.wet()
  else
    event = capabilities.waterSensor.water.dry()
  end

  if event ~= nil then
    device:emit_event(event)
  end
end

local ias_zone_status_attr_handler = function(driver, device, zone_status, zb_rx)
  generate_event_from_zone_status(driver, device, zone_status, zb_rx)
end

local ias_zone_status_change_handler = function(driver, device, zb_rx)
  generate_event_from_zone_status(driver, device, zb_rx.body.zcl_body.zone_status, zb_rx)
end


local sinope_water_sensor = {
  NAME = "Sinope Water Leak Sensor",
  zigbee_handlers = {
    attr = {
      [IASZone.ID] = {
        [IASZone.attributes.ZoneStatus.ID] = ias_zone_status_attr_handler
      }
    },
    cluster = {
      [IASZone.ID] = {
        [IASZone.client.commands.ZoneStatusChangeNotification.ID] = ias_zone_status_change_handler
      }
    }
  },
  can_handle = require("sinope.can_handle"),
}

return sinope_water_sensor
