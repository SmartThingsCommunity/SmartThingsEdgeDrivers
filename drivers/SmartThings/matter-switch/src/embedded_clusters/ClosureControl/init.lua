local cluster_base = require "st.matter.cluster_base"
local lazy_require = require "st.utils.lazy_require"

local ClosureControl = {}

ClosureControl.ID = 0x0104
ClosureControl.NAME = "ClosureControl"
ClosureControl.server = {}
ClosureControl.client = {}
ClosureControl.server.attributes = lazy_require "ClosureControl.server.attributes"
ClosureControl.server.commands = lazy_require "ClosureControl.server.commands"
ClosureControl.types = lazy_require "ClosureControl.types"

ClosureControl.FeatureMap = ClosureControl.types.Feature

function ClosureControl.are_features_supported(feature, feature_map)
  if (ClosureControl.FeatureMap.bits_are_valid(feature)) then
    return (feature & feature_map) == feature
  end
  return false
end

ClosureControl.attributes = ClosureControl.server.attributes

ClosureControl.commands = setmetatable({}, {
  __index = function(_self, key)
    local command = ClosureControl.server.commands[key]
    if command then
      return command
    end
    local client_commands = ClosureControl.client.commands
    return client_commands and client_commands[key]
  end,
})

setmetatable(ClosureControl, {__index = cluster_base})

return ClosureControl
