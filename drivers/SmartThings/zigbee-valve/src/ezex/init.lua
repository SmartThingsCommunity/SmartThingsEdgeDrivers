-- Copyright 2024 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"

local IASZone = clusters.IASZone
local Basic = clusters.Basic
local OnOff = clusters.OnOff

local configuration = {
  {
    cluster = IASZone.ID,
    attribute = IASZone.attributes.ZoneStatus.ID,
    minimum_interval = 0,
    maximum_interval = 3600,
    data_type = IASZone.attributes.ZoneStatus.base_type,
    reportable_change = 1
  },
  {
    cluster = Basic.ID,
    attribute = Basic.attributes.PowerSource.ID,
    minimum_interval = 30,
    maximum_interval = 21600,
    data_type = Basic.attributes.PowerSource.base_type,
  },
  {
    cluster = OnOff.ID,
    attribute = OnOff.attributes.OnOff.ID,
    minimum_interval = 0,
    maximum_interval = 600,
    data_type = OnOff.attributes.OnOff.base_type
  }
}

local function ias_zone_status_attr_handler(driver, device, zone_status, zb_rx)
  -- this is cribbed from the DTH
  if zone_status:is_battery_low_set() then
    device:emit_event(capabilities.battery.battery(5))
  else
    device:emit_event(capabilities.battery.battery(50))
  end
end

local function device_init(driver, device)
  for _, attribute in ipairs(configuration) do
    device:add_configured_attribute(attribute)
  end
end

local ezex_valve = {
  NAME = "Ezex Valve",
  zigbee_handlers = {
    attr = {
      [IASZone.ID] = {
        [IASZone.attributes.ZoneStatus.ID] = ias_zone_status_attr_handler
      },
    }
  },
  lifecycle_handlers = {
    init = device_init
  },
  can_handle = require("ezex.can_handle"),
}

return ezex_valve
