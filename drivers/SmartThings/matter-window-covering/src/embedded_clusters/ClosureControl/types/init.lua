local types_mt = {}
types_mt.__index = function(self, key)
  return require("embedded_clusters.ClosureControl.types." .. key)
end

local ClosureControlTypes = {}

setmetatable(ClosureControlTypes, types_mt)

return ClosureControlTypes
