-- Copyright 2024 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local IASZone = (require "st.zigbee.zcl.clusters").IASZone
local log = require "log"



local configuration = {
  {
    cluster = IASZone.ID,
    attribute = IASZone.attributes.ZoneStatus.ID,
    minimum_interval = 0,
    maximum_interval = 3600,
    data_type = IASZone.attributes.ZoneStatus.base_type,
    reportable_change = 1
  }
}

local function present_value_attr_handler(driver, device, zone_status, zb_rx)
  log.info("present_value_attr_handler The current value is: ", zone_status.value)
  local status = zone_status
  local button

  local additional_fields = {
    state_change = true
  }
  local event
  local mod = status.value % 6
  if mod == 1 then
    event = capabilities.button.button.pushed(additional_fields)
  elseif mod == 3 then
    event = capabilities.button.button.double(additional_fields)
  elseif mod == 5 then
    event = capabilities.button.button.held(additional_fields)
  end

  if (event) then
    button = string.format("button%d", status.value // 6 + 1)
    device:emit_component_event(device.profile.components[button], event)
  end
end

local function device_init(driver, device)
  for _, attribute in ipairs(configuration) do
    device:add_configured_attribute(attribute)
  end
end

local linxura_device_handler = {
  NAME = "Linxura Device Handler",
  lifecycle_handlers = {
    init = device_init
  },

  zigbee_handlers = {
    attr = {
      [IASZone.ID] = {
        [IASZone.attributes.ZoneStatus.ID] = present_value_attr_handler
      }
    }
  },

  can_handle = require("zigbee-multi-button.linxura.can_handle"),
}

return linxura_device_handler
