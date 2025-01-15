local cluster_base = require "st.matter.cluster_base"
local ModeSelectServerCommands = require "ModeSelect.server.commands"

local ModeSelect = {}

ModeSelect.ID = 0x0050
ModeSelect.NAME = "ModeSelect"
ModeSelect.server = {}
ModeSelect.client = {}
ModeSelect.server.commands = ModeSelectServerCommands:set_parent_cluster(ModeSelect)

function ModeSelect:get_server_command_by_id(command_id)
  local server_id_map = {
    [0x0000] = "ChangeToMode",
  }
  if server_id_map[command_id] ~= nil then
    return self.server.commands[server_id_map[command_id]]
  end
  return nil
end

-- Command Mapping
ModeSelect.command_direction_map = {
  ["ChangeToMode"] = "server",
}

do
  local has_aliases, aliases = pcall(require, "ModeSelect.server.commands")
  if has_aliases then
    for alias, _ in pairs(aliases) do
      ModeSelect.command_direction_map[alias] = "server"
    end
  end
end

local command_helper_mt = {}
command_helper_mt.__index = function(self, key)
  local direction = ModeSelect.command_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown command %s on cluster %s", key, ModeSelect.NAME))
  end
  return ModeSelect[direction].commands[key]
end
ModeSelect.commands = {}
setmetatable(ModeSelect.commands, command_helper_mt)

local event_helper_mt = {}
event_helper_mt.__index = function(self, key)
  return ModeSelect.server.events[key]
end
ModeSelect.events = {}
setmetatable(ModeSelect.events, event_helper_mt)

setmetatable(ModeSelect, {__index = cluster_base})

return ModeSelect

