















local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"










local ErrorStateEnum = {}
local new_mt = UintABC.new_mt({NAME = "ErrorStateEnum", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.NO_ERROR] = "NO_ERROR",
    [self.UNABLE_TO_START_OR_RESUME] = "UNABLE_TO_START_OR_RESUME",
    [self.UNABLE_TO_COMPLETE_OPERATION] = "UNABLE_TO_COMPLETE_OPERATION",
    [self.COMMAND_INVALID_IN_STATE] = "COMMAND_INVALID_IN_STATE",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.NO_ERROR  = 0x00
new_mt.__index.UNABLE_TO_START_OR_RESUME  = 0x01
new_mt.__index.UNABLE_TO_COMPLETE_OPERATION  = 0x02
new_mt.__index.COMMAND_INVALID_IN_STATE  = 0x03

ErrorStateEnum.NO_ERROR  = 0x00
ErrorStateEnum.UNABLE_TO_START_OR_RESUME  = 0x01
ErrorStateEnum.UNABLE_TO_COMPLETE_OPERATION  = 0x02
ErrorStateEnum.COMMAND_INVALID_IN_STATE  = 0x03

ErrorStateEnum.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(ErrorStateEnum, new_mt)

return ErrorStateEnum
