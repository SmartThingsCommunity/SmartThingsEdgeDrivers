-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local st_device = require "st.device"
local device_management = require "st.zigbee.device_management"
local inovelli_common = require "inovelli.common"

local OccupancySensing = clusters.OccupancySensing

local PRIVATE_CLUSTER_ID = 0xFC31
local MFG_CODE = 0x122F


local function configure_illuminance_reporting(device)
  local min_lux_change = 15
  local value = math.floor(10000 * math.log(min_lux_change, 10) + 1)
  device:send(clusters.IlluminanceMeasurement.attributes.MeasuredValue:configure_reporting(device, 10, 600, value))
end

local function refresh_handler(driver, device, command)
  if device.network_type ~= st_device.NETWORK_TYPE_CHILD then
    device:refresh()
    device:send(OccupancySensing.attributes.Occupancy:read(device))
  else
    device:refresh()
  end
end

local function device_added(driver, device)
  if device.network_type ~= st_device.NETWORK_TYPE_CHILD then
    refresh_handler(driver, device, {})
  else
    device:emit_event(capabilities.colorControl.hue(1))
    device:emit_event(capabilities.colorControl.saturation(1))
    device:emit_event(capabilities.colorTemperature.colorTemperatureRange({ value = {minimum = 2700, maximum = 6500} }))
    device:emit_event(capabilities.colorTemperature.colorTemperature(6500))
    device:emit_event(capabilities.switchLevel.level(100))
    device:emit_event(capabilities.switch.switch("off"))
  end
end

local function device_configure(driver, device)
  if device.network_type ~= st_device.NETWORK_TYPE_CHILD then
    inovelli_common.base_device_configure(driver, device, PRIVATE_CLUSTER_ID, MFG_CODE)
    device:send(device_management.build_bind_request(device, OccupancySensing.ID, driver.environment_info.hub_zigbee_eui))
    configure_illuminance_reporting(device)
  else
    device:configure()
  end
end

local vzm32_sn = {
  NAME = "Inovelli VZM32-SN mmWave Dimmer",
  can_handle = require("inovelli.vzm32-sn.can_handle"),
  lifecycle_handlers = {
    added = device_added,
    doConfigure = device_configure,
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = refresh_handler,
    }
  }
}

return vzm32_sn