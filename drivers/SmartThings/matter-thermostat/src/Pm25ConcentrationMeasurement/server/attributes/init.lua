local attr_mt = {}
attr_mt.__attr_cache = {}
attr_mt.__index = function(self, key)
  if attr_mt.__attr_cache[key] == nil then
    local req_loc = string.format("Pm25ConcentrationMeasurement.server.attributes.%s", key)
    local raw_def = require(req_loc)
    local cluster = rawget(self, "_cluster")
    raw_def:set_parent_cluster(cluster)
    attr_mt.__attr_cache[key] = raw_def
  end
  return attr_mt.__attr_cache[key]
end

local Pm25ConcentrationMeasurementServerAttributes = {}

function Pm25ConcentrationMeasurementServerAttributes:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

setmetatable(Pm25ConcentrationMeasurementServerAttributes, attr_mt)

return Pm25ConcentrationMeasurementServerAttributes

