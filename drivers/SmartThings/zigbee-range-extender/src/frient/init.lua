-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"

local IASZone = clusters.IASZone
local PowerConfiguration = clusters.PowerConfiguration

local function generate_event_from_zone_status(driver, device, zone_status, zigbee_message)
  device:emit_event_for_endpoint(
    zigbee_message.address_header.src_endpoint.value,
    zone_status:is_ac_mains_fault_set() and capabilities.powerSource.powerSource.battery() or capabilities.powerSource.powerSource.mains()
  )
end

local function ias_zone_status_attr_handler(driver, device, zone_status, zb_rx)
  generate_event_from_zone_status(driver, device, zone_status, zb_rx)
end

local function ias_zone_status_change_handler(driver, device, zb_rx)
  generate_event_from_zone_status(driver, device, zb_rx.body.zcl_body.zone_status, zb_rx)
end

local function device_added(driver, device)
  device:emit_event(capabilities.powerSource.powerSource.mains())
end

local function device_init(driver, device)
  battery_defaults.build_linear_voltage_init(3.3, 4.1)(driver, device)
end

local function do_refresh(driver, device)
  device:send(PowerConfiguration.attributes.BatteryVoltage:read(device))
  device:send(IASZone.attributes.ZoneStatus:read(device))
end

local frient_range_extender = {
  NAME = "frient Range Extender",
  lifecycle_handlers = {
    added = device_added,
    init = device_init
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    }
  },
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
  can_handle = require("frient.can_handle"),
}

return frient_range_extender
