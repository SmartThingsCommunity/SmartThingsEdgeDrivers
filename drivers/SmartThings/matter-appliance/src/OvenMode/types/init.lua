local types_mt = {}
types_mt.__types_cache = {}
types_mt.__index = function(self, key)
  if types_mt.__types_cache[key] == nil then
    types_mt.__types_cache[key] = require("OvenMode.types." .. key)
  end
  return types_mt.__types_cache[key]
end

local OvenModeTypes = {}

setmetatable(OvenModeTypes, types_mt)

return OvenModeTypes

