local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local DoorLockSetPinOrIdStatus = {}
local new_mt = UintABC.new_mt({NAME = "DoorLockSetPinOrIdStatus", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.SUCCESS] = "SUCCESS",
    [self.GENERAL_FAILURE] = "GENERAL_FAILURE",
    [self.MEMORY_FULL] = "MEMORY_FULL",
    [self.DUPLICATE_CODE_ERROR] = "DUPLICATE_CODE_ERROR",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.SUCCESS  = 0x00
new_mt.__index.GENERAL_FAILURE  = 0x01
new_mt.__index.MEMORY_FULL  = 0x02
new_mt.__index.DUPLICATE_CODE_ERROR  = 0x03

DoorLockSetPinOrIdStatus.SUCCESS  = 0x00
DoorLockSetPinOrIdStatus.GENERAL_FAILURE  = 0x01
DoorLockSetPinOrIdStatus.MEMORY_FULL  = 0x02
DoorLockSetPinOrIdStatus.DUPLICATE_CODE_ERROR  = 0x03

DoorLockSetPinOrIdStatus.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(DoorLockSetPinOrIdStatus, new_mt)

return DoorLockSetPinOrIdStatus