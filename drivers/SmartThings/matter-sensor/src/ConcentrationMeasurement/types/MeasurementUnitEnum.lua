local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local MeasurementUnitEnum = {}
-- Note: the name here is intentionally set to Uint8 to maintain backwards compatibility
-- with how types were handled in api < 10.
local new_mt = UintABC.new_mt({NAME = "Uint8", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.PPM] = "PPM",
    [self.PPB] = "PPB",
    [self.PPT] = "PPT",
    [self.MGM3] = "MGM3",
    [self.UGM3] = "UGM3",
    [self.NGM3] = "NGM3",
    [self.PM3] = "PM3",
    [self.BQM3] = "BQM3",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.PPM  = 0x00
new_mt.__index.PPB  = 0x01
new_mt.__index.PPT  = 0x02
new_mt.__index.MGM3  = 0x03
new_mt.__index.UGM3  = 0x04
new_mt.__index.NGM3  = 0x05
new_mt.__index.PM3  = 0x06
new_mt.__index.BQM3  = 0x07

MeasurementUnitEnum.PPM  = 0x00
MeasurementUnitEnum.PPB  = 0x01
MeasurementUnitEnum.PPT  = 0x02
MeasurementUnitEnum.MGM3  = 0x03
MeasurementUnitEnum.UGM3  = 0x04
MeasurementUnitEnum.NGM3  = 0x05
MeasurementUnitEnum.PM3  = 0x06
MeasurementUnitEnum.BQM3  = 0x07

MeasurementUnitEnum.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(MeasurementUnitEnum, new_mt)

return MeasurementUnitEnum

