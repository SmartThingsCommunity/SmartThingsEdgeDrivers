-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local version = require "version"
local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local embedded_cluster_utils = require "sensor_utils.embedded_cluster_utils"
local fields = require "sub_drivers.air_quality_sensor.air_quality_sensor_utils.fields"

local DeviceConfiguration = {}

function DeviceConfiguration.supported_level_measurements(device)
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

function DeviceConfiguration.match_profile(device)
  local update_metadata_request = require "sensor_utils.update_metadata_request"

  local temp_eps = embedded_cluster_utils.get_endpoints(device, clusters.TemperatureMeasurement.ID)
  local humidity_eps = embedded_cluster_utils.get_endpoints(device, clusters.RelativeHumidityMeasurement.ID)

  local updated_metadata = update_metadata_request.init()
  local preference_tags = ""

  if #temp_eps > 0 then
    updated_metadata:add_capabilities_to_component("main", { capabilities.temperatureMeasurement.ID })
    preference_tags = preference_tags .. "-temp"
  end
  if #humidity_eps > 0 then
    updated_metadata:add_capabilities_to_component("main", { capabilities.relativeHumidityMeasurement.ID })
    preference_tags = preference_tags .. "-humidity"
  end

  local measurement_caps, level_caps = DeviceConfiguration.supported_level_measurements(device)
  updated_metadata:add_capabilities_to_component("main", measurement_caps)
  updated_metadata:add_capabilities_to_component("main", level_caps)

  device:try_update_metadata(updated_metadata:add_profile("aqs-modular" .. preference_tags):format())

  -- earlier modular profile gating (min api v14, rpc 8) ensures we are running >= 0.57 FW.
  -- This gating specifies a workaround required only for 0.57 FW, which is not needed for 0.58 and higher.
  if version.api < 15 or version.rpc < 9 then
    local MAIN_COMPONENT_IDX = 1
    local CAPABILITIES_LIST_IDX = 2
    -- add mandatory capabilities for subscription
    local total_supported_capabilities = updated_metadata:formatted_enabled_components()
    table.insert(total_supported_capabilities[MAIN_COMPONENT_IDX][CAPABILITIES_LIST_IDX], capabilities.airQualityHealthConcern.ID)
    table.insert(total_supported_capabilities[MAIN_COMPONENT_IDX][CAPABILITIES_LIST_IDX], capabilities.refresh.ID)
    table.insert(total_supported_capabilities[MAIN_COMPONENT_IDX][CAPABILITIES_LIST_IDX], capabilities.firmwareUpdate.ID)

    device:set_field(fields.SUPPORTED_COMPONENT_CAPABILITIES, total_supported_capabilities, { persist = true })
  end
end

return DeviceConfiguration