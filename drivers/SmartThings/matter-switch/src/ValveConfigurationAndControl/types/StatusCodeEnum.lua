local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"
local StatusCodeEnum = {}
local new_mt = UintABC.new_mt({NAME = "StatusCodeEnum", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.FAILURE_DUE_TO_FAULT] = "FAILURE_DUE_TO_FAULT",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.FAILURE_DUE_TO_FAULT  = 0x02

StatusCodeEnum.FAILURE_DUE_TO_FAULT  = 0x02

StatusCodeEnum.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(StatusCodeEnum, new_mt)

local has_aliases, aliases = pcall(require, "st.matter.clusters.aliases.ValveConfigurationAndControl.types.StatusCodeEnum")
if has_aliases then
  aliases:add_to_class(StatusCodeEnum)
end

return StatusCodeEnum
