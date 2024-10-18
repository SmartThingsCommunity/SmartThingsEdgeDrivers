local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local DataOperationTypeEnum = {}
local new_mt = UintABC.new_mt({NAME = "DataOperationTypeEnum", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.ADD] = "ADD",
    [self.CLEAR] = "CLEAR",
    [self.MODIFY] = "MODIFY",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.ADD  = 0x00
new_mt.__index.CLEAR  = 0x01
new_mt.__index.MODIFY  = 0x02

DataOperationTypeEnum.ADD  = 0x00
DataOperationTypeEnum.CLEAR  = 0x01
DataOperationTypeEnum.MODIFY  = 0x02

DataOperationTypeEnum.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(DataOperationTypeEnum, new_mt)

return DataOperationTypeEnum