local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local StatusCode = {}
local new_mt = UintABC.new_mt({NAME = "StatusCode", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.STUCK] = "STUCK",
    [self.DUST_BIN_MISSING] = "DUST_BIN_MISSING",
    [self.DUST_BIN_FULL] = "DUST_BIN_FULL",
    [self.WATER_TANK_EMPTY] = "WATER_TANK_EMPTY",
    [self.WATER_TANK_MISSING] = "WATER_TANK_MISSING",
    [self.WATER_TANK_LID_OPEN] = "WATER_TANK_LID_OPEN",
    [self.MOP_CLEANING_PAD_MISSING] = "MOP_CLEANING_PAD_MISSING",
    [self.BATTERY_LOW] = "BATTERY_LOW",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.STUCK  = 0x41
new_mt.__index.DUST_BIN_MISSING  = 0x42
new_mt.__index.DUST_BIN_FULL  = 0x43
new_mt.__index.WATER_TANK_EMPTY  = 0x44
new_mt.__index.WATER_TANK_MISSING  = 0x45
new_mt.__index.WATER_TANK_LID_OPEN  = 0x46
new_mt.__index.MOP_CLEANING_PAD_MISSING  = 0x47
new_mt.__index.BATTERY_LOW  = 0x48

StatusCode.STUCK  = 0x41
StatusCode.DUST_BIN_MISSING  = 0x42
StatusCode.DUST_BIN_FULL  = 0x43
StatusCode.WATER_TANK_EMPTY  = 0x44
StatusCode.WATER_TANK_MISSING  = 0x45
StatusCode.WATER_TANK_LID_OPEN  = 0x46
StatusCode.MOP_CLEANING_PAD_MISSING  = 0x47
StatusCode.BATTERY_LOW  = 0x48

StatusCode.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(StatusCode, new_mt)

return StatusCode

