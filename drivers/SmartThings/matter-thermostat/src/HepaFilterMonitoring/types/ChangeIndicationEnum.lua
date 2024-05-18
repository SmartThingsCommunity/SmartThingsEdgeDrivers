local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local ChangeIndicationEnum = {}
local new_mt = UintABC.new_mt({NAME = "ChangeIndicationEnum", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.OK] = "OK",
    [self.WARNING] = "WARNING",
    [self.CRITICAL] = "CRITICAL",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.OK  = 0x00
new_mt.__index.WARNING  = 0x01
new_mt.__index.CRITICAL  = 0x02

ChangeIndicationEnum.OK  = 0x00
ChangeIndicationEnum.WARNING  = 0x01
ChangeIndicationEnum.CRITICAL  = 0x02

ChangeIndicationEnum.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(ChangeIndicationEnum, new_mt)

local has_aliases, aliases = pcall(require, "st.matter.clusters.aliases.HepaFilterMonitoring.types.ChangeIndicationEnum")
if has_aliases then
  aliases:add_to_class(ChangeIndicationEnum)
end

return ChangeIndicationEnum

