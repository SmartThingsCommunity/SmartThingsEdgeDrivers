local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local MainStateEnum = {}
local new_mt = UintABC.new_mt({NAME = "MainStateEnum", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.STOPPED] = "STOPPED",
    [self.MOVING] = "MOVING",
    [self.WAITING_FOR_MOTION] = "WAITING_FOR_MOTION",
    [self.ERROR] = "ERROR",
    [self.CALIBRATING] = "CALIBRATING",
    [self.PROTECTED] = "PROTECTED",
    [self.DISENGAGED] = "DISENGAGED",
    [self.SETUP_REQUIRED] = "SETUP_REQUIRED",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.STOPPED  = 0x00
new_mt.__index.MOVING  = 0x01
new_mt.__index.WAITING_FOR_MOTION  = 0x02
new_mt.__index.ERROR  = 0x03
new_mt.__index.CALIBRATING  = 0x04
new_mt.__index.PROTECTED  = 0x05
new_mt.__index.DISENGAGED  = 0x06
new_mt.__index.SETUP_REQUIRED  = 0x07

MainStateEnum.STOPPED  = 0x00
MainStateEnum.MOVING  = 0x01
MainStateEnum.WAITING_FOR_MOTION  = 0x02
MainStateEnum.ERROR  = 0x03
MainStateEnum.CALIBRATING  = 0x04
MainStateEnum.PROTECTED  = 0x05
MainStateEnum.DISENGAGED  = 0x06
MainStateEnum.SETUP_REQUIRED  = 0x07

MainStateEnum.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(MainStateEnum, new_mt)

return MainStateEnum
