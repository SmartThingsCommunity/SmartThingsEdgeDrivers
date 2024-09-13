local command_mt = {}
command_mt.__command_cache = {}
command_mt.__index = function(self, key)
  if command_mt.__command_cache[key] == nil then
    local req_loc = string.format("EnergyEvse.server.commands.%s", key)
    local raw_def = require(req_loc)
    local cluster = rawget(self, "_cluster")
    command_mt.__command_cache[key] = raw_def:set_parent_cluster(cluster)
  end
  return command_mt.__command_cache[key]
end

local EnergyEvseServerCommands = {}

function EnergyEvseServerCommands:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

setmetatable(EnergyEvseServerCommands, command_mt)

return EnergyEvseServerCommands

