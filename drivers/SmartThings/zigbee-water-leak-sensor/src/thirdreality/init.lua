-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local utils = require "st.utils"

local Basic = zcl_clusters.Basic
local PowerConfiguration = zcl_clusters.PowerConfiguration

local APPLICATION_VERSION = "application_version"



local function device_added(driver, device)
  device:set_field(APPLICATION_VERSION, 0)
  device:send(Basic.attributes.ApplicationVersion:read(device))
end

local function application_version_attr_handler(driver, device, value, zb_rx)
  local version = tonumber(value.value)
  device:set_field(APPLICATION_VERSION, version, {persist = true})
end

local function battery_percentage_handler(driver, device, value, zb_rx)
  local softwareVersion = device:get_field(APPLICATION_VERSION)
  local percentage

  if softwareVersion and softwareVersion <= 0x17 then
    -- Version 1.0.23 (23 == 0x17) and earlier incorrectly reports battery percentage
    percentage = utils.clamp_value(value.value, 0, 100)
  else
    percentage = utils.clamp_value(utils.round(value.value / 2), 0, 100)
  end

  device:emit_event(capabilities.battery.battery(percentage))
end

local third_reality_water_leak_sensor = {
  NAME = "Third Reality water leak sensor",
  zigbee_handlers = {
    attr = {
      [Basic.ID] = {
        [Basic.attributes.ApplicationVersion.ID] = application_version_attr_handler
      },
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryPercentageRemaining.ID] = battery_percentage_handler
      }
    }
  },
  lifecycle_handlers = {
    added = device_added
  },
  can_handle = require("thirdreality.can_handle"),
}

return third_reality_water_leak_sensor
