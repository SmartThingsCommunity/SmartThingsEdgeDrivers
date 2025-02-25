local types_mt = {}
types_mt.__types_cache = {}
types_mt.__index = function(self, key)
  if types_mt.__types_cache[key] == nil then
    types_mt.__types_cache[key] = require("ElectricalEnergyMeasurement.types." .. key)
  end
  return types_mt.__types_cache[key]
end

local ElectricalEnergyMeasurementTypes = {}

setmetatable(ElectricalEnergyMeasurementTypes, types_mt)

return ElectricalEnergyMeasurementTypes

