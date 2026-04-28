local types_mt = {}
types_mt.__index = function(self, key)
  return require("embedded_clusters.ClosureDimension.types." .. key)
end

local ClosureDimensionTypes = {}

setmetatable(ClosureDimensionTypes, types_mt)

return ClosureDimensionTypes
