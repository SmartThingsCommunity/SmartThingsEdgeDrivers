local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local DlStatus = {}
local new_mt = UintABC.new_mt({NAME = "DlStatus", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.SUCCESS] = "SUCCESS",
    [self.FAILURE] = "FAILURE",
    [self.DUPLICATE] = "DUPLICATE",
    [self.OCCUPIED] = "OCCUPIED",
    [self.INVALID_FIELD] = "INVALID_FIELD",
    [self.RESOURCE_EXHAUSTED] = "RESOURCE_EXHAUSTED",
    [self.NOT_FOUND] = "NOT_FOUND",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.SUCCESS  = 0x00
new_mt.__index.FAILURE  = 0x01
new_mt.__index.DUPLICATE  = 0x02
new_mt.__index.OCCUPIED  = 0x03
new_mt.__index.INVALID_FIELD  = 0x85
new_mt.__index.RESOURCE_EXHAUSTED  = 0x89
new_mt.__index.NOT_FOUND  = 0x8B

DlStatus.SUCCESS  = 0x00
DlStatus.FAILURE  = 0x01
DlStatus.DUPLICATE  = 0x02
DlStatus.OCCUPIED  = 0x03
DlStatus.INVALID_FIELD  = 0x85
DlStatus.RESOURCE_EXHAUSTED  = 0x89
DlStatus.NOT_FOUND  = 0x8B

DlStatus.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(DlStatus, new_mt)

return DlStatus