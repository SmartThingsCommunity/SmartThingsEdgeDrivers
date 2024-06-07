local clusters = require "st.matter.clusters"
local utils = require "st.utils"

-- Include driver-side definitions when lua libs api version is < 10
local version = require "version"
if version.api < 10 then
  clusters.HepaFilterMonitoring = require "HepaFilterMonitoring"
  clusters.ActivatedCarbonFilterMonitoring = require "ActivatedCarbonFilterMonitoring"
end

local embedded_cluster_utils = {}

local embedded_clusters = {
  [clusters.HepaFilterMonitoring.ID] = clusters.HepaFilterMonitoring,
  [clusters.ActivatedCarbonFilterMonitoring.ID] = clusters.ActivatedCarbonFilterMonitoring
}

function embedded_cluster_utils.get_endpoints(device, cluster_id, opts)
  -- If using older lua libs and need to check for an embedded cluster feature,
  -- we must use the embedded cluster definitions here
  if version.api < 10 and embedded_clusters[cluster_id] ~= nil then
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
    return eps
  else
    return device:get_endpoints(cluster_id, opts)
  end
end

return embedded_cluster_utils