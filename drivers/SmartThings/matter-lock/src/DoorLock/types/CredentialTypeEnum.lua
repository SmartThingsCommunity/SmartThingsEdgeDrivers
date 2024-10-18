local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local CredentialTypeEnum = {}
local new_mt = UintABC.new_mt({NAME = "CredentialTypeEnum", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.PROGRAMMINGPIN] = "PROGRAMMINGPIN",
    [self.PIN] = "PIN",
    [self.RFID] = "RFID",
    [self.FINGERPRINT] = "FINGERPRINT",
    [self.FINGER_VEIN] = "FINGER_VEIN",
    [self.FACE] = "FACE",
    [self.ALIRO_CREDENTIAL_ISSUER_KEY] = "ALIRO_CREDENTIAL_ISSUER_KEY",
    [self.ALIRO_EVICTABLE_ENDPOINT_KEY] = "ALIRO_EVICTABLE_ENDPOINT_KEY",
    [self.ALIRO_NON_EVICTABLE_ENDPOINT_KEY] = "ALIRO_NON_EVICTABLE_ENDPOINT_KEY",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.PROGRAMMINGPIN  = 0x00
new_mt.__index.PIN  = 0x01
new_mt.__index.RFID  = 0x02
new_mt.__index.FINGERPRINT  = 0x03
new_mt.__index.FINGER_VEIN  = 0x04
new_mt.__index.FACE  = 0x05
new_mt.__index.ALIRO_CREDENTIAL_ISSUER_KEY  = 0x06
new_mt.__index.ALIRO_EVICTABLE_ENDPOINT_KEY  = 0x07
new_mt.__index.ALIRO_NON_EVICTABLE_ENDPOINT_KEY  = 0x08

CredentialTypeEnum.PROGRAMMINGPIN  = 0x00
CredentialTypeEnum.PIN  = 0x01
CredentialTypeEnum.RFID  = 0x02
CredentialTypeEnum.FINGERPRINT  = 0x03
CredentialTypeEnum.FINGER_VEIN  = 0x04
CredentialTypeEnum.FACE  = 0x05
CredentialTypeEnum.ALIRO_CREDENTIAL_ISSUER_KEY  = 0x06
CredentialTypeEnum.ALIRO_EVICTABLE_ENDPOINT_KEY  = 0x07
CredentialTypeEnum.ALIRO_NON_EVICTABLE_ENDPOINT_KEY  = 0x08

CredentialTypeEnum.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(CredentialTypeEnum, new_mt)

return CredentialTypeEnum