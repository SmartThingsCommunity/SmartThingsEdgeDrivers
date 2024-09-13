local clusters = require "st.matter.clusters"
local utils = require "st.utils"
local version = require "version"

if version.api < 11 then
  clusters.ElectricalPowerMeasurement = require "ElectricalPowerMeasurement"
  clusters.ElectricalEnergyMeasurement = require "ElectricalEnergyMeasurement"
  clusters.EnergyEvse = require "EnergyEvse"
  clusters.EnergyEvseMode = require "EnergyEvseMode"
end

--this cluster is not supported in any releases of the lua libs
clusters.DeviceEnergyManagementMode = require "DeviceEnergyManagementMode"

local embedded_cluster_utils = {}

local embedded_clusters = {
  [clusters.ElectricalPowerMeasurement.ID] = clusters.ElectricalPowerMeasurement,
  [clusters.EnergyEvse.ID] = clusters.EnergyEvse,
  [clusters.DeviceEnergyManagementMode.ID] = clusters.DeviceEnergyManagementMode,
  [clusters.ElectricalEnergyMeasurement.ID] = clusters.ElectricalEnergyMeasurement,
  [clusters.EnergyEvseMode.ID] = clusters.EnergyEvseMode,
}

function embedded_cluster_utils.get_endpoints(device, cluster_id, opts)
    if embedded_clusters[cluster_id] ~= nil then
      local embedded_cluster = embedded_clusters[cluster_id]
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
      table.sort(eps)
      return eps
    else
      local eps = device:get_endpoints(cluster_id, opts)
      table.sort(eps)
      return eps
    end
  end

  return embedded_cluster_utils