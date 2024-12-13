local clusters = require "st.matter.clusters"
local utils = require "st.utils"

local version = require "version"
if version.api < 10 then
  clusters.ActivatedCarbonFilterMonitoring = require "ActivatedCarbonFilterMonitoring"
  clusters.DishwasherAlarm = require "DishwasherAlarm"
  clusters.DishwasherMode = require "DishwasherMode"
  clusters.HepaFilterMonitoring = require "HepaFilterMonitoring"
  clusters.LaundryWasherControls = require "LaundryWasherControls"
  clusters.LaundryWasherMode = require "LaundryWasherMode"
  clusters.OperationalState = require "OperationalState"
  clusters.RefrigeratorAlarm = require "RefrigeratorAlarm"
  clusters.RefrigeratorAndTemperatureControlledCabinetMode = require "RefrigeratorAndTemperatureControlledCabinetMode"
  clusters.TemperatureControl = require "TemperatureControl"
end

if version.api < 11 then
  clusters.MicrowaveOvenControl = require "MicrowaveOvenControl"
  clusters.MicrowaveOvenMode = require "MicrowaveOvenMode"
end

-- this cluster is not supported in any release of the lua libs
clusters.OvenMode = require "OvenMode"

local embedded_cluster_utils = {}

local embedded_clusters = {
  [clusters.ActivatedCarbonFilterMonitoring.ID] = clusters.ActivatedCarbonFilterMonitoring,
  [clusters.DishwasherAlarm.ID] = clusters.DishwasherAlarm,
  [clusters.DishwasherMode.ID] = clusters.DishwasherMode,
  [clusters.HepaFilterMonitoring.ID] = clusters.HepaFilterMonitoring,
  [clusters.LaundryWasherControls.ID] = clusters.LaundryWasherControls,
  [clusters.LaundryWasherMode.ID] = clusters.LaundryWasherMode,
  [clusters.OperationalState.ID] = clusters.OperationalState,
  [clusters.RefrigeratorAlarm.ID] = clusters.RefrigeratorAlarm,
  [clusters.RefrigeratorAndTemperatureControlledCabinetMode.ID] = clusters.RefrigeratorAndTemperatureControlledCabinetMode,
  [clusters.TemperatureControl.ID] = clusters.TemperatureControl,
  [clusters.MicrowaveOvenControl.ID] = clusters.MicrowaveOvenControl,
  [clusters.MicrowaveOvenMode.ID] = clusters.MicrowaveOvenMode,
  [clusters.OvenMode.ID] = clusters.OvenMode,
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