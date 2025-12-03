-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local types_mt = {}
types_mt.__index = function(self, key)
  return require("embedded_clusters.PowerTopology.types." .. key)
end

local PowerTopologyTypes = {}

setmetatable(PowerTopologyTypes, types_mt)

return PowerTopologyTypes

