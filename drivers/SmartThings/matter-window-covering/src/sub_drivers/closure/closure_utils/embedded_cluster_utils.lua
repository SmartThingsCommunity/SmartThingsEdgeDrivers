-- Copyright © 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local clusters = require "st.matter.clusters"
local utils = require "st.utils"
local version = require "version"

if version.api < 20 then
  clusters.ClosureControl = require "embedded_clusters.ClosureControl"
  clusters.ClosureDimension = require "embedded_clusters.ClosureDimension"
end

if version.api < 16 then
  clusters.Descriptor = require "embedded_clusters.Descriptor"
end

local embedded_cluster_utils = {}

local embedded_clusters_16 = {
  [clusters.Descriptor.ID] = clusters.Descriptor
}

local embedded_clusters_20 = {
  [clusters.ClosureControl.ID] = clusters.ClosureControl,
  [clusters.ClosureDimension.ID] = clusters.ClosureDimension
}

function embedded_cluster_utils.get_endpoints(device, cluster_id, opts)
    -- If using older lua libs and need to check for an embedded cluster feature,
    -- we must use the embedded cluster definitions here
    if (version.api < 16 and embedded_clusters_16[cluster_id] ~= nil)
       or (version.api < 20 and embedded_clusters_20[cluster_id] ~= nil) then
      local embedded_cluster = embedded_clusters_16[cluster_id] or embedded_clusters_20[cluster_id]
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
