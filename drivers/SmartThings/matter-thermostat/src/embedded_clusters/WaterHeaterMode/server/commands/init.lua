-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local command_mt = {}
command_mt.__command_cache = {}
command_mt.__index = function(self, key)
  if command_mt.__command_cache[key] == nil then
    local req_loc = string.format("embedded_clusters.WaterHeaterMode.server.commands.%s", key)
    local raw_def = require(req_loc)
    local cluster = rawget(self, "_cluster")
    command_mt.__command_cache[key] = raw_def:set_parent_cluster(cluster)
  end
  return command_mt.__command_cache[key]
end

local WaterHeaterModeServerCommands = {}

function WaterHeaterModeServerCommands:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

setmetatable(WaterHeaterModeServerCommands, command_mt)

return WaterHeaterModeServerCommands

