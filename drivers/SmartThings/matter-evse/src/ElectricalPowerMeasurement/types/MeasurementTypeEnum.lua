local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local MeasurementTypeEnum = {}
local new_mt = UintABC.new_mt({NAME = "MeasurementTypeEnum", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.UNSPECIFIED] = "UNSPECIFIED",
    [self.VOLTAGE] = "VOLTAGE",
    [self.ACTIVE_CURRENT] = "ACTIVE_CURRENT",
    [self.REACTIVE_CURRENT] = "REACTIVE_CURRENT",
    [self.APPARENT_CURRENT] = "APPARENT_CURRENT",
    [self.ACTIVE_POWER] = "ACTIVE_POWER",
    [self.REACTIVE_POWER] = "REACTIVE_POWER",
    [self.APPARENT_POWER] = "APPARENT_POWER",
    [self.RMS_VOLTAGE] = "RMS_VOLTAGE",
    [self.RMS_CURRENT] = "RMS_CURRENT",
    [self.RMS_POWER] = "RMS_POWER",
    [self.FREQUENCY] = "FREQUENCY",
    [self.POWER_FACTOR] = "POWER_FACTOR",
    [self.NEUTRAL_CURRENT] = "NEUTRAL_CURRENT",
    [self.ELECTRICAL_ENERGY] = "ELECTRICAL_ENERGY",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.UNSPECIFIED  = 0x00
new_mt.__index.VOLTAGE  = 0x01
new_mt.__index.ACTIVE_CURRENT  = 0x02
new_mt.__index.REACTIVE_CURRENT  = 0x03
new_mt.__index.APPARENT_CURRENT  = 0x04
new_mt.__index.ACTIVE_POWER  = 0x05
new_mt.__index.REACTIVE_POWER  = 0x06
new_mt.__index.APPARENT_POWER  = 0x07
new_mt.__index.RMS_VOLTAGE  = 0x08
new_mt.__index.RMS_CURRENT  = 0x09
new_mt.__index.RMS_POWER  = 0x0A
new_mt.__index.FREQUENCY  = 0x0B
new_mt.__index.POWER_FACTOR  = 0x0C
new_mt.__index.NEUTRAL_CURRENT  = 0x0D
new_mt.__index.ELECTRICAL_ENERGY  = 0x0E

MeasurementTypeEnum.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(MeasurementTypeEnum, new_mt)

return MeasurementTypeEnum

