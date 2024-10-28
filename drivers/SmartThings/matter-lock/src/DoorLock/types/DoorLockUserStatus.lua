local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local DoorLockUserStatus = {}
local new_mt = UintABC.new_mt({NAME = "DoorLockUserStatus", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.AVAILABLE] = "AVAILABLE",
    [self.OCCUPIED_ENABLED] = "OCCUPIED_ENABLED",
    [self.OCCUPIED_DISABLED] = "OCCUPIED_DISABLED",
    [self.NOT_SUPPORTED] = "NOT_SUPPORTED",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.AVAILABLE  = 0x00
new_mt.__index.OCCUPIED_ENABLED  = 0x01
new_mt.__index.OCCUPIED_DISABLED  = 0x03
new_mt.__index.NOT_SUPPORTED  = 0xFF

DoorLockUserStatus.AVAILABLE  = 0x00
DoorLockUserStatus.OCCUPIED_ENABLED  = 0x01
DoorLockUserStatus.OCCUPIED_DISABLED  = 0x03
DoorLockUserStatus.NOT_SUPPORTED  = 0xFF

DoorLockUserStatus.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(DoorLockUserStatus, new_mt)

return DoorLockUserStatus