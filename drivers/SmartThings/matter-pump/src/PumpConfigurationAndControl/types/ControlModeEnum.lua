local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local ControlModeEnum = {}
-- Note: the name here is intentionally set to Uint8 to maintain backwards compatibility
-- with how types were handled in api < 10.
local new_mt = UintABC.new_mt({NAME = "Uint8", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.CONSTANT_SPEED] = "CONSTANT_SPEED",
    [self.CONSTANT_PRESSURE] = "CONSTANT_PRESSURE",
    [self.PROPORTIONAL_PRESSURE] = "PROPORTIONAL_PRESSURE",
    [self.CONSTANT_FLOW] = "CONSTANT_FLOW",
    [self.CONSTANT_TEMPERATURE] = "CONSTANT_TEMPERATURE",
    [self.AUTOMATIC] = "AUTOMATIC",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.CONSTANT_SPEED  = 0x00
new_mt.__index.CONSTANT_PRESSURE  = 0x01
new_mt.__index.PROPORTIONAL_PRESSURE  = 0x02
new_mt.__index.CONSTANT_FLOW  = 0x03
new_mt.__index.CONSTANT_TEMPERATURE  = 0x05
new_mt.__index.AUTOMATIC  = 0x07

ControlModeEnum.CONSTANT_SPEED  = 0x00
ControlModeEnum.CONSTANT_PRESSURE  = 0x01
ControlModeEnum.PROPORTIONAL_PRESSURE  = 0x02
ControlModeEnum.CONSTANT_FLOW  = 0x03
ControlModeEnum.CONSTANT_TEMPERATURE  = 0x05
ControlModeEnum.AUTOMATIC  = 0x07

ControlModeEnum.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(ControlModeEnum, new_mt)

local has_aliases, aliases = pcall(require, "st.matter.clusters.aliases.PumpConfigurationAndControl.types.ControlModeEnum")
if has_aliases then
  aliases:add_to_class(ControlModeEnum)
end

return ControlModeEnum
