-- Copyright 2022 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

-- sub driver of the Zigbee Power Meter
-- need to add the attribute battery percentage remaining (0x0021)  from the Power Configuration Cluster (0x0001)
-- need to add the attribute current temperature  (0x0000)          from the Temperature Configuration Cluster (0x002)


--
-- SmartThings Edge Zigbee Subdriver for Battery Percentage (Power Configuration Cluster)
--
-- This module provides the logic to configure and handle the Battery Percentage Remaining
-- attribute (0x0021) from the ZCL Power Configuration Cluster (0x0001).
--
local capabilities = require "st.capabilities"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local log = require "log"

-- Constants for the Power Configuration Cluster
local POWER_CONFIG_CLUSTER_ID = zcl_clusters.PowerConfiguration.ID
local BATTERY_PERCENTAGE_REMAINING_ATTR = zcl_clusters.PowerConfiguration.attributes.BatteryPercentageRemaining.ID

-- The attribute value is reported in 0.5% increments, so 200 is 100%.
local MAX_PERCENT_RAW = 200

-- Configuration: Report once every 6 hours (min/max interval) with a minimum change of 2% (4 in raw units)
local BATTERY_REPORTING_CONFIG = {
  {
    cluster = POWER_CONFIG_CLUSTER_ID,
    attribute = BATTERY_PERCENTAGE_REMAINING_ATTR,
    -- min_reporting_interval: 1 hour (3600 seconds)
    minimum_reporting_interval = 3600,
    -- max_reporting_interval: 6 hours (21600 seconds)
    maximum_reporting_interval = 21600,
    -- reportable_change: 2% (or 4 units, since 2 units = 1%)
    reportable_change = 4,
  }
}

--- Function to handle the raw BatteryPercentageRemaining attribute report.
--- @param driver ZigbeeDriver
--- @param device ZigbeeDevice
--- @param cmd ZclAttributeReport or ZclReadAttributeResponse
local function handle_battery_percentage(driver, device, cmd)
  -- The value is reported in units of 0.5%
  local raw_value = cmd.body.attribute_value.value
  local percentage = raw_value / 2

  -- Clamp the value between 0 and 100
  local final_percentage = math.max(0, math.min(100, percentage))

  driver:emit(device, capabilities.battery.battery(final_percentage))
  device:emit_event(capabilities.refresh.refresh()) -- Also refresh the device status
  driver:log_debug(string.format(
    "Received Battery Percentage Report for %s: Raw=%d, Final=%d%%",
    device.label, raw_value, final_percentage
  ))
end

--- Function to set up the reporting configuration when the device is first configured or comes online.
--- @param driver ZigbeeDriver
--- @param device ZigbeeDevice
local function do_battery_config(driver, device)
  driver:log_info(string.format("Configuring battery reporting for %s", device.label))
  
  -- Send the configuration commands
  for _, config in ipairs(BATTERY_REPORTING_CONFIG) do
    local status, result = device:configure_reporting(
      config.cluster,
      config.attribute,
      config.minimum_reporting_interval,
      config.maximum_reporting_interval,
      config.reportable_change
    )
  end
end

local battery_percentage_subdriver = {
  -- Add a handler to configure battery reporting when the device is first configured.
  -- You would typically call this from the 'added' or 'online' lifecycle event of your main driver.
  lifecycle = {
    added = do_battery_config,
    online = do_battery_config, -- In case the device was previously configured
  },

  -- Add the handler for incoming attribute reports from the Power Configuration Cluster (0x0001)
  -- and the specific Battery Percentage Remaining attribute (0x0021).
  handlers = {
    -- This uses the standard handler generator pattern
    -- The third argument specifies the attribute ID (0x0021)
    [zcl_clusters.PowerConfiguration.ID] = {
      [BATTERY_PERCENTAGE_REMAINING_ATTR] = handle_battery_percentage,
    }
  },

  -- Export the configuration function so it can be called manually if needed
  -- or if you prefer to manage config flow externally.
  do_battery_config = do_battery_config,
}
log.debug ("battery_percentage_subdriver")
return battery_percentage_subdriver

