local types_mt = {}
types_mt.__types_cache = {}
types_mt.__index = function(self, key)
  if types_mt.__types_cache[key] == nil then
    types_mt.__types_cache[key] = require("ActivatedCarbonFilterMonitoring.types." .. key)
  end
  return types_mt.__types_cache[key]
end

local ActivatedCarbonFilterMonitoringTypes = {}

setmetatable(ActivatedCarbonFilterMonitoringTypes, types_mt)

local status, aliases = pcall(require, "st.matter.clusters.aliases.ActivatedCarbonFilterMonitoring.types")
if status then
  aliases:add_to_class(ActivatedCarbonFilterMonitoringTypes)
end

return ActivatedCarbonFilterMonitoringTypes

