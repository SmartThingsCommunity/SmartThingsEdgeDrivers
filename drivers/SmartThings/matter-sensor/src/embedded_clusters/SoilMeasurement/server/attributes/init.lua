local attr_mt = {}
attr_mt.__index = function(self, key)
  local req_loc = string.format("embedded_clusters.SoilMeasurement.server.attributes.%s", key)
  local raw_def = require(req_loc)
  local cluster = rawget(self, "_cluster")
  raw_def:set_parent_cluster(cluster)
  return raw_def
end

local SoilMeasurementServerAttributes = {}

function SoilMeasurementServerAttributes:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

setmetatable(SoilMeasurementServerAttributes, attr_mt)

return SoilMeasurementServerAttributes
