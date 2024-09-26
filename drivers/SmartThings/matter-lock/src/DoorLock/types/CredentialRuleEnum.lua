local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local CredentialRuleEnum = {}
local new_mt = UintABC.new_mt({NAME = "CredentialRuleEnum", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.SINGLE] = "SINGLE",
    [self.DUAL] = "DUAL",
    [self.TRI] = "TRI",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.SINGLE  = 0x00
new_mt.__index.DUAL  = 0x01
new_mt.__index.TRI  = 0x02

CredentialRuleEnum.SINGLE  = 0x00
CredentialRuleEnum.DUAL  = 0x01
CredentialRuleEnum.TRI  = 0x02

CredentialRuleEnum.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(CredentialRuleEnum, new_mt)

return CredentialRuleEnum

