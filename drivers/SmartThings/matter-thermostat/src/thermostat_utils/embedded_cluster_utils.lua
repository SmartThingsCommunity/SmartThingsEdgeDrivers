-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0
local version = require "version"
local clusters = require "st.matter.clusters"
local utils = require "st.utils"

if version.api < 10 then
  clusters.HepaFilterMonitoring = require "embedded_clusters.HepaFilterMonitoring"
  clusters.ActivatedCarbonFilterMonitoring = require "embedded_clusters.ActivatedCarbonFilterMonitoring"
  clusters.AirQuality = require "embedded_clusters.AirQuality"
  clusters.CarbonMonoxideConcentrationMeasurement = require "embedded_clusters.CarbonMonoxideConcentrationMeasurement"
  clusters.CarbonDioxideConcentrationMeasurement = require "embedded_clusters.CarbonDioxideConcentrationMeasurement"
  clusters.FormaldehydeConcentrationMeasurement = require "embedded_clusters.FormaldehydeConcentrationMeasurement"
  clusters.NitrogenDioxideConcentrationMeasurement = require "embedded_clusters.NitrogenDioxideConcentrationMeasurement"
  clusters.OzoneConcentrationMeasurement = require "embedded_clusters.OzoneConcentrationMeasurement"
  clusters.Pm1ConcentrationMeasurement = require "embedded_clusters.Pm1ConcentrationMeasurement"
  clusters.Pm10ConcentrationMeasurement = require "embedded_clusters.Pm10ConcentrationMeasurement"
  clusters.Pm25ConcentrationMeasurement = require "embedded_clusters.Pm25ConcentrationMeasurement"
  clusters.RadonConcentrationMeasurement = require "embedded_clusters.RadonConcentrationMeasurement"
  clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement = require "embedded_clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement"
end

if version.api < 11 then
  clusters.ElectricalEnergyMeasurement = require "embedded_clusters.ElectricalEnergyMeasurement"
  clusters.ElectricalPowerMeasurement = require "embedded_clusters.ElectricalPowerMeasurement"
end

if version.api < 13 then
  clusters.WaterHeaterMode = require "embedded_clusters.WaterHeaterMode"
end

local embedded_cluster_utils = {}

local embedded_clusters_api_10 = {
  [clusters.HepaFilterMonitoring.ID] = clusters.HepaFilterMonitoring,
  [clusters.ActivatedCarbonFilterMonitoring.ID] = clusters.ActivatedCarbonFilterMonitoring,
  [clusters.AirQuality.ID] = clusters.AirQuality,
  [clusters.CarbonMonoxideConcentrationMeasurement.ID] = clusters.CarbonMonoxideConcentrationMeasurement,
  [clusters.CarbonDioxideConcentrationMeasurement.ID] = clusters.CarbonDioxideConcentrationMeasurement,
  [clusters.FormaldehydeConcentrationMeasurement.ID] = clusters.FormaldehydeConcentrationMeasurement,
  [clusters.NitrogenDioxideConcentrationMeasurement.ID] = clusters.NitrogenDioxideConcentrationMeasurement,
  [clusters.OzoneConcentrationMeasurement.ID] = clusters.OzoneConcentrationMeasurement,
  [clusters.Pm1ConcentrationMeasurement.ID] = clusters.Pm1ConcentrationMeasurement,
  [clusters.Pm10ConcentrationMeasurement.ID] = clusters.Pm10ConcentrationMeasurement,
  [clusters.Pm25ConcentrationMeasurement.ID] = clusters.Pm25ConcentrationMeasurement,
  [clusters.RadonConcentrationMeasurement.ID] = clusters.RadonConcentrationMeasurement,
  [clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.ID] = clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement,
}

local embedded_clusters_api_11 = {
  [clusters.ElectricalEnergyMeasurement.ID] = clusters.ElectricalEnergyMeasurement,
  [clusters.ElectricalPowerMeasurement.ID] = clusters.ElectricalPowerMeasurement,
}

local embedded_clusters_api_13 = {
  [clusters.WaterHeaterMode.ID] = clusters.WaterHeaterMode
}

function embedded_cluster_utils.get_endpoints(device, cluster_id, opts)
  -- If using older lua libs and need to check for an embedded cluster feature,
  -- we must use the embedded cluster definitions here
  if version.api < 10 and embedded_clusters_api_10[cluster_id] ~= nil or
     version.api < 11 and embedded_clusters_api_11[cluster_id] ~= nil or
     version.api < 13 and embedded_clusters_api_13[cluster_id] ~= nil then
    local embedded_cluster = embedded_clusters_api_10[cluster_id] or embedded_clusters_api_11[cluster_id] or embedded_clusters_api_13[cluster_id]
    local opts = opts or {}
    if utils.table_size(opts) > 1 then
      device.log.warn_with({hub_logs = true}, "Invalid options for get_endpoints")
      return
    end
    local clus_has_features = function(clus, feature_bitmap)
      if not feature_bitmap or not clus then return false end
      return embedded_cluster.are_features_supported(feature_bitmap, clus.feature_map)
    end
    local eps = {}
    for _, ep in ipairs(device.endpoints) do
      for _, clus in ipairs(ep.clusters) do
        if ((clus.cluster_id == cluster_id)
              and (opts.feature_bitmap == nil or clus_has_features(clus, opts.feature_bitmap))
              and ((opts.cluster_type == nil and clus.cluster_type == "SERVER" or clus.cluster_type == "BOTH")
                or (opts.cluster_type == clus.cluster_type))
              or (cluster_id == nil)) then
          table.insert(eps, ep.endpoint_id)
          if cluster_id == nil then break end
        end
      end
    end
    return eps
  else
    return device:get_endpoints(cluster_id, opts)
  end
end

return embedded_cluster_utils