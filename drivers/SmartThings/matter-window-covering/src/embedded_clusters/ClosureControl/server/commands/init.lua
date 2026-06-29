local command_mt = {}
command_mt.__index = function(self, key)
  local req_loc = string.format("embedded_clusters.ClosureControl.server.commands.%s", key)
  local raw_def = require(req_loc)
  local cluster = rawget(self, "_cluster")
  raw_def:set_parent_cluster(cluster)
  return raw_def
end

local ClosureControlServerCommands = {}

function ClosureControlServerCommands:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

setmetatable(ClosureControlServerCommands, command_mt)

return ClosureControlServerCommands
