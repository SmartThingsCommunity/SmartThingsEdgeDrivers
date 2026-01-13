-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local version = require "version"
local fields = require "switch_utils.fields"
local switch_utils = require "switch_utils.utils"
local embedded_cluster_utils = require "switch_utils.embedded_cluster_utils"

local ContactDeviceConfiguration = {}
local FlowDeviceConfiguration = {}
local WaterFreezeDetectorDeviceConfiguration = {}
local IlluminanceDeviceConfiguration = {}
local WaterLeakDetectorDeviceConfiguration = {}
local RainDeviceConfiguration = {}
local PressureDeviceConfiguration = {}

local TempHumiditySensorConfiguration = {}

local MotionDeviceConfiguration = {} -- OccupancySensorConfiguration


function MotionDeviceConfiguration.assign_profile_for_occupancy_sensor_ep(device, occupancy_ep_id)
  local ep_info = switch_utils.get_endpoint_info(device, occupancy_ep_id)
  local generic_profile = "motion"
  -- If the Occupancy Sensing Cluster’s revision is >= 5 (corresponds to Lua Libs version 13+), and any of the AIR / RAD / RFS / VIS
  -- features are supported by the device, use the presenceSensor capability.
  local f = clusters.OccupancySensing.types.Feature
  local feature_bitmap = f.ACTIVE_INFRARED & f.RADAR & f.RF_SENSING & f.VISION
  if version.api >= 13 and #switch_utils.find_cluster_on_ep(ep_info, clusters.OccupancySensing.ID, {feature_bitmap = feature_bitmap}) > 0 then
    generic_profile = "-presence"
  end

  return generic_profile
end

return MotionDeviceConfiguration
