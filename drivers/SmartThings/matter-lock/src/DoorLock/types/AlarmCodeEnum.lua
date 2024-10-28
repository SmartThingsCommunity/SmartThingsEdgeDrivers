local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local AlarmCodeEnum = {}
local new_mt = UintABC.new_mt({NAME = "AlarmCodeEnum", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.LOCK_JAMMED] = "LOCK_JAMMED",
    [self.LOCK_FACTORY_RESET] = "LOCK_FACTORY_RESET",
    [self.LOCK_RADIO_POWER_CYCLED] = "LOCK_RADIO_POWER_CYCLED",
    [self.WRONG_CODE_ENTRY_LIMIT] = "WRONG_CODE_ENTRY_LIMIT",
    [self.FRONT_ESCEUTCHEON_REMOVED] = "FRONT_ESCEUTCHEON_REMOVED",
    [self.DOOR_FORCED_OPEN] = "DOOR_FORCED_OPEN",
    [self.DOOR_AJAR] = "DOOR_AJAR",
    [self.FORCED_USER] = "FORCED_USER",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.LOCK_JAMMED  = 0x00
new_mt.__index.LOCK_FACTORY_RESET  = 0x01
new_mt.__index.LOCK_RADIO_POWER_CYCLED  = 0x03
new_mt.__index.WRONG_CODE_ENTRY_LIMIT  = 0x04
new_mt.__index.FRONT_ESCEUTCHEON_REMOVED  = 0x05
new_mt.__index.DOOR_FORCED_OPEN  = 0x06
new_mt.__index.DOOR_AJAR  = 0x07
new_mt.__index.FORCED_USER  = 0x08

AlarmCodeEnum.LOCK_JAMMED  = 0x00
AlarmCodeEnum.LOCK_FACTORY_RESET  = 0x01
AlarmCodeEnum.LOCK_RADIO_POWER_CYCLED  = 0x03
AlarmCodeEnum.WRONG_CODE_ENTRY_LIMIT  = 0x04
AlarmCodeEnum.FRONT_ESCEUTCHEON_REMOVED  = 0x05
AlarmCodeEnum.DOOR_FORCED_OPEN  = 0x06
AlarmCodeEnum.DOOR_AJAR  = 0x07
AlarmCodeEnum.FORCED_USER  = 0x08

AlarmCodeEnum.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(AlarmCodeEnum, new_mt)

return AlarmCodeEnum