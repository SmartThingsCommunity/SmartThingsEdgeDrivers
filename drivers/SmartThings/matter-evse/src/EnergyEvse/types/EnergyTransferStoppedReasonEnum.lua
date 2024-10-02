local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local EnergyTransferStoppedReasonEnum = {}
local new_mt = UintABC.new_mt({NAME = "EnergyTransferStoppedReasonEnum", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.EV_STOPPED] = "EV_STOPPED",
    [self.EVSE_STOPPED] = "EVSE_STOPPED",
    [self.OTHER] = "OTHER",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.EV_STOPPED  = 0x00
new_mt.__index.EVSE_STOPPED  = 0x01
new_mt.__index.OTHER  = 0x02

EnergyTransferStoppedReasonEnum.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(EnergyTransferStoppedReasonEnum, new_mt)

return EnergyTransferStoppedReasonEnum
