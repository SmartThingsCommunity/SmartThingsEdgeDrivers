local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local OperationalStateEnum = {}
local new_mt = UintABC.new_mt({NAME = "OperationalStateEnum", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.SEEKING_CHARGER] = "SEEKING_CHARGER",
    [self.CHARGING] = "CHARGING",
    [self.DOCKED] = "DOCKED",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.SEEKING_CHARGER  = 0x40
new_mt.__index.CHARGING  = 0x41
new_mt.__index.DOCKED  = 0x42

OperationalStateEnum.SEEKING_CHARGER  = 0x40
OperationalStateEnum.CHARGING  = 0x41
OperationalStateEnum.DOCKED  = 0x42

OperationalStateEnum.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(OperationalStateEnum, new_mt)

return OperationalStateEnum

