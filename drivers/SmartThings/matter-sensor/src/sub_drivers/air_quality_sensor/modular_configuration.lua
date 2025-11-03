-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local embedded_cluster_utils = require "sensor_utils.embedded_cluster_utils"
local fields = require "sub_drivers.air_quality_sensor.fields"
local version = require "version"

local function supported_level_measurements(device)
  local measurement_caps, level_caps = {}, {}
  for _, cap in ipairs(fields.CONCENTRATION_MEASUREMENT_PROFILE_ORDERING) do
    local cap_id  = cap.ID
    local cluster = fields.CONCENTRATION_MEASUREMENT_MAP[cap][2]
    -- capability describes either a HealthConcern or Measurement/Sensor
    if (cap_id:match("HealthConcern$")) then
      local attr_eps = embedded_cluster_utils.get_endpoints(device, cluster.ID, { feature_bitmap = cluster.types.Feature.LEVEL_INDICATION })
      if #attr_eps > 0 then
        table.insert(level_caps, cap_id)
      end
    elseif (cap_id:match("Measurement$") or cap_id:match("Sensor$")) then
      local attr_eps = embedded_cluster_utils.get_endpoints(device, cluster.ID, { feature_bitmap = cluster.types.Feature.NUMERIC_MEASUREMENT })
      if #attr_eps > 0 then
        table.insert(measurement_caps, cap_id)
      end
    end
  end
  return measurement_caps, level_caps
end

-- Match Modular Profile
return function(device)
  local temp_eps = embedded_cluster_utils.get_endpoints(device, clusters.TemperatureMeasurement.ID)
  local humidity_eps = embedded_cluster_utils.get_endpoints(device, clusters.RelativeHumidityMeasurement.ID)

  local optional_supported_component_capabilities = {}
  local main_component_capabilities = {}
  local profile_name
  local MAIN_COMPONENT_IDX = 1
  local CAPABILITIES_LIST_IDX = 2

  if #temp_eps > 0 then
    table.insert(main_component_capabilities, capabilities.temperatureMeasurement.ID)
  end
  if #humidity_eps > 0 then
    table.insert(main_component_capabilities, capabilities.relativeHumidityMeasurement.ID)
  end

  local measurement_caps, level_caps = supported_level_measurements(device)

  for _, cap_id in ipairs(measurement_caps) do
    table.insert(main_component_capabilities, cap_id)
  end

  for _, cap_id in ipairs(level_caps) do
    table.insert(main_component_capabilities, cap_id)
  end

  table.insert(optional_supported_component_capabilities, {"main", main_component_capabilities})

  if #temp_eps > 0 and #humidity_eps > 0 then
    profile_name = "aqs-modular-temp-humidity"
  elseif #temp_eps > 0 then
    profile_name = "aqs-modular-temp"
  elseif #humidity_eps > 0 then
    profile_name = "aqs-modular-humidity"
  else
    profile_name = "aqs-modular"
  end

  device:try_update_metadata({profile = profile_name, optional_component_capabilities = optional_supported_component_capabilities})

  -- earlier modular profile gating (min api v14, rpc 8) ensures we are running >= 0.57 FW.
  -- This gating specifies a workaround required only for 0.57 FW, which is not needed for 0.58 and higher.
  if version.api < 15 or version.rpc < 9 then
    -- add mandatory capabilities for subscription
    local total_supported_capabilities = optional_supported_component_capabilities
    table.insert(total_supported_capabilities[MAIN_COMPONENT_IDX][CAPABILITIES_LIST_IDX], capabilities.airQualityHealthConcern.ID)
    table.insert(total_supported_capabilities[MAIN_COMPONENT_IDX][CAPABILITIES_LIST_IDX], capabilities.refresh.ID)
    table.insert(total_supported_capabilities[MAIN_COMPONENT_IDX][CAPABILITIES_LIST_IDX], capabilities.firmwareUpdate.ID)

    device:set_field(fields.SUPPORTED_COMPONENT_CAPABILITIES, total_supported_capabilities, { persist = true })
  end
end
