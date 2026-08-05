local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local DoorLockProgrammingEventCode = {}
local new_mt = UintABC.new_mt({NAME = "DoorLockProgrammingEventCode", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.UNKNOWN_OR_MFG_SPECIFIC] = "UNKNOWN_OR_MFG_SPECIFIC",
    [self.MASTER_CODE_CHANGED] = "MASTER_CODE_CHANGED",
    [self.PIN_ADDED] = "PIN_ADDED",
    [self.PIN_DELETED] = "PIN_DELETED",
    [self.PIN_CHANGED] = "PIN_CHANGED",
    [self.ID_ADDED] = "ID_ADDED",
    [self.ID_DELETED] = "ID_DELETED",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.UNKNOWN_OR_MFG_SPECIFIC  = 0x00
new_mt.__index.MASTER_CODE_CHANGED  = 0x01
new_mt.__index.PIN_ADDED  = 0x02
new_mt.__index.PIN_DELETED  = 0x03
new_mt.__index.PIN_CHANGED  = 0x04
new_mt.__index.ID_ADDED  = 0x05
new_mt.__index.ID_DELETED  = 0x06

DoorLockProgrammingEventCode.UNKNOWN_OR_MFG_SPECIFIC  = 0x00
DoorLockProgrammingEventCode.MASTER_CODE_CHANGED  = 0x01
DoorLockProgrammingEventCode.PIN_ADDED  = 0x02
DoorLockProgrammingEventCode.PIN_DELETED  = 0x03
DoorLockProgrammingEventCode.PIN_CHANGED  = 0x04
DoorLockProgrammingEventCode.ID_ADDED  = 0x05
DoorLockProgrammingEventCode.ID_DELETED  = 0x06

DoorLockProgrammingEventCode.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(DoorLockProgrammingEventCode, new_mt)

return DoorLockProgrammingEventCode