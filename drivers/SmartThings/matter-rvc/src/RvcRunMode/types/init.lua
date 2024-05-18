local types_mt = {}
types_mt.__types_cache = {}
types_mt.__index = function(self, key)
  if types_mt.__types_cache[key] == nil then
    types_mt.__types_cache[key] = require("RvcRunMode.types." .. key)
  end
  return types_mt.__types_cache[key]
end

local RvcRunModeTypes = {}

setmetatable(RvcRunModeTypes, types_mt)

local status, aliases = pcall(require, "st.matter.clusters.aliases.RvcRunMode.types")
if status then
  aliases:add_to_class(RvcRunModeTypes)
end

return RvcRunModeTypes

