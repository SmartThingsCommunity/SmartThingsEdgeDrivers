local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local OperationSourceEnum = {}
local new_mt = UintABC.new_mt({NAME = "OperationSourceEnum", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.UNSPECIFIED] = "UNSPECIFIED",
    [self.MANUAL] = "MANUAL",
    [self.PROPRIETARY_REMOTE] = "PROPRIETARY_REMOTE",
    [self.KEYPAD] = "KEYPAD",
    [self.AUTO] = "AUTO",
    [self.BUTTON] = "BUTTON",
    [self.SCHEDULE] = "SCHEDULE",
    [self.REMOTE] = "REMOTE",
    [self.RFID] = "RFID",
    [self.BIOMETRIC] = "BIOMETRIC",
    [self.ALIRO] = "ALIRO",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.UNSPECIFIED  = 0x00
new_mt.__index.MANUAL  = 0x01
new_mt.__index.PROPRIETARY_REMOTE  = 0x02
new_mt.__index.KEYPAD  = 0x03
new_mt.__index.AUTO  = 0x04
new_mt.__index.BUTTON  = 0x05
new_mt.__index.SCHEDULE  = 0x06
new_mt.__index.REMOTE  = 0x07
new_mt.__index.RFID  = 0x08
new_mt.__index.BIOMETRIC  = 0x09
new_mt.__index.ALIRO  = 0x0A

OperationSourceEnum.UNSPECIFIED  = 0x00
OperationSourceEnum.MANUAL  = 0x01
OperationSourceEnum.PROPRIETARY_REMOTE  = 0x02
OperationSourceEnum.KEYPAD  = 0x03
OperationSourceEnum.AUTO  = 0x04
OperationSourceEnum.BUTTON  = 0x05
OperationSourceEnum.SCHEDULE  = 0x06
OperationSourceEnum.REMOTE  = 0x07
OperationSourceEnum.RFID  = 0x08
OperationSourceEnum.BIOMETRIC  = 0x09
OperationSourceEnum.ALIRO  = 0x0A

OperationSourceEnum.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(OperationSourceEnum, new_mt)

return OperationSourceEnum