local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local AlarmStateEnum = {}
-- Note: the name here is intentionally set to Uint8 to maintain backwards compatibility
-- with how types were handled in api < 10.
local new_mt = UintABC.new_mt({NAME = "Uint8", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.NORMAL] = "NORMAL",
    [self.WARNING] = "WARNING",
    [self.CRITICAL] = "CRITICAL",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.NORMAL  = 0x00
new_mt.__index.WARNING  = 0x01
new_mt.__index.CRITICAL  = 0x02

AlarmStateEnum.NORMAL  = 0x00
AlarmStateEnum.WARNING  = 0x01
AlarmStateEnum.CRITICAL  = 0x02

AlarmStateEnum.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(AlarmStateEnum, new_mt)

return AlarmStateEnum

