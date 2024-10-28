local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local SupplyStateEnum = {}
local new_mt = UintABC.new_mt({NAME = "SupplyStateEnum", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.DISABLED] = "DISABLED",
    [self.CHARGING_ENABLED] = "CHARGING_ENABLED",
    [self.DISCHARGING_ENABLED] = "DISCHARGING_ENABLED",
    [self.DISABLED_ERROR] = "DISABLED_ERROR",
    [self.DISABLED_DIAGNOSTICS] = "DISABLED_DIAGNOSTICS",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.DISABLED  = 0x00
new_mt.__index.CHARGING_ENABLED  = 0x01
new_mt.__index.DISCHARGING_ENABLED  = 0x02
new_mt.__index.DISABLED_ERROR  = 0x03
new_mt.__index.DISABLED_DIAGNOSTICS  = 0x04

SupplyStateEnum.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(SupplyStateEnum, new_mt)

return SupplyStateEnum
