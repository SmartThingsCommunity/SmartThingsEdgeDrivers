local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local LockOperationTypeEnum = {}
local new_mt = UintABC.new_mt({NAME = "LockOperationTypeEnum", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.LOCK] = "LOCK",
    [self.UNLOCK] = "UNLOCK",
    [self.NON_ACCESS_USER_EVENT] = "NON_ACCESS_USER_EVENT",
    [self.FORCED_USER_EVENT] = "FORCED_USER_EVENT",
    [self.UNLATCH] = "UNLATCH",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.LOCK  = 0x00
new_mt.__index.UNLOCK  = 0x01
new_mt.__index.NON_ACCESS_USER_EVENT  = 0x02
new_mt.__index.FORCED_USER_EVENT  = 0x03
new_mt.__index.UNLATCH  = 0x04

LockOperationTypeEnum.LOCK  = 0x00
LockOperationTypeEnum.UNLOCK  = 0x01
LockOperationTypeEnum.NON_ACCESS_USER_EVENT  = 0x02
LockOperationTypeEnum.FORCED_USER_EVENT  = 0x03
LockOperationTypeEnum.UNLATCH  = 0x04

LockOperationTypeEnum.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(LockOperationTypeEnum, new_mt)

return LockOperationTypeEnum