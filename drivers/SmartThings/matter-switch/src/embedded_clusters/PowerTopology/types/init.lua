local types_mt = {}
types_mt.__index = function(self, key)
  return require("embedded_clusters.PowerTopology.types." .. key)
end

local PowerTopologyTypes = {}

setmetatable(PowerTopologyTypes, types_mt)

return PowerTopologyTypes

