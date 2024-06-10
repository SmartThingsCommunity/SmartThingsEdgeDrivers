local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local OperationalStateEnum = {}
-- Note: the name here is intentionally set to Uint8 to maintain backwards compatibility
-- with how types were handled in api < 10.
local new_mt = UintABC.new_mt({NAME = "Uint8", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.STOPPED] = "STOPPED",
    [self.RUNNING] = "RUNNING",
    [self.PAUSED] = "PAUSED",
    [self.ERROR] = "ERROR",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.STOPPED  = 0x00
new_mt.__index.RUNNING  = 0x01
new_mt.__index.PAUSED  = 0x02
new_mt.__index.ERROR  = 0x03

OperationalStateEnum.STOPPED  = 0x00
OperationalStateEnum.RUNNING  = 0x01
OperationalStateEnum.PAUSED  = 0x02
OperationalStateEnum.ERROR  = 0x03

OperationalStateEnum.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(OperationalStateEnum, new_mt)

return OperationalStateEnum
