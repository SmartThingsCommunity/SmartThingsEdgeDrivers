local command_mt = {}
command_mt.__command_cache = {}
command_mt.__index = function(self, key)
  if command_mt.__command_cache[key] == nil then
    local req_loc = string.format("ThreadBorderRouterManagement.server.commands.%s", key)
    local raw_def = require(req_loc)
    local cluster = rawget(self, "_cluster")
    command_mt.__command_cache[key] = raw_def:set_parent_cluster(cluster)
  end
  return command_mt.__command_cache[key]
end

local ThreadBorderRouterManagementServerCommands = {}

function ThreadBorderRouterManagementServerCommands:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

setmetatable(ThreadBorderRouterManagementServerCommands, command_mt)

local status, aliases = pcall(require, "st.matter.clusters.aliases.ThreadBorderRouterManagement.server.commands")
if status then
  aliases:add_to_class(ThreadBorderRouterManagementServerCommands)
end

return ThreadBorderRouterManagementServerCommands

