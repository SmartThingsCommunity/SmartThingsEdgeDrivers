local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local FaultStateEnum = {}
local new_mt = UintABC.new_mt({NAME = "FaultStateEnum", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.NO_ERROR] = "NO_ERROR",
    [self.METER_FAILURE] = "METER_FAILURE",
    [self.OVER_VOLTAGE] = "OVER_VOLTAGE",
    [self.UNDER_VOLTAGE] = "UNDER_VOLTAGE",
    [self.OVER_CURRENT] = "OVER_CURRENT",
    [self.CONTACT_WET_FAILURE] = "CONTACT_WET_FAILURE",
    [self.CONTACT_DRY_FAILURE] = "CONTACT_DRY_FAILURE",
    [self.GROUND_FAULT] = "GROUND_FAULT",
    [self.POWER_LOSS] = "POWER_LOSS",
    [self.POWER_QUALITY] = "POWER_QUALITY",
    [self.PILOT_SHORT_CIRCUIT] = "PILOT_SHORT_CIRCUIT",
    [self.EMERGENCY_STOP] = "EMERGENCY_STOP",
    [self.EV_DISCONNECTED] = "EV_DISCONNECTED",
    [self.WRONG_POWER_SUPPLY] = "WRONG_POWER_SUPPLY",
    [self.LIVE_NEUTRAL_SWAP] = "LIVE_NEUTRAL_SWAP",
    [self.OVER_TEMPERATURE] = "OVER_TEMPERATURE",
    [self.OTHER] = "OTHER",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.NO_ERROR  = 0x00
new_mt.__index.METER_FAILURE  = 0x01
new_mt.__index.OVER_VOLTAGE  = 0x02
new_mt.__index.UNDER_VOLTAGE  = 0x03
new_mt.__index.OVER_CURRENT  = 0x04
new_mt.__index.CONTACT_WET_FAILURE  = 0x05
new_mt.__index.CONTACT_DRY_FAILURE  = 0x06
new_mt.__index.GROUND_FAULT  = 0x07
new_mt.__index.POWER_LOSS  = 0x08
new_mt.__index.POWER_QUALITY  = 0x09
new_mt.__index.PILOT_SHORT_CIRCUIT  = 0x0A
new_mt.__index.EMERGENCY_STOP  = 0x0B
new_mt.__index.EV_DISCONNECTED  = 0x0C
new_mt.__index.WRONG_POWER_SUPPLY  = 0x0D
new_mt.__index.LIVE_NEUTRAL_SWAP  = 0x0E
new_mt.__index.OVER_TEMPERATURE  = 0x0F
new_mt.__index.OTHER  = 0xFF

FaultStateEnum.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(FaultStateEnum, new_mt)

return FaultStateEnum
