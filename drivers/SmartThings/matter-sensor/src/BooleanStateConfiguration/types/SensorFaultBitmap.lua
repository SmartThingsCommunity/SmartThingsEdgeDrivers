local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local SensorFaultBitmap = {}
local new_mt = UintABC.new_mt({NAME = "SensorFaultBitmap", ID = data_types.name_to_id_map["Uint16"]}, 2)

SensorFaultBitmap.BASE_MASK = 0xFFFF
SensorFaultBitmap.GENERAL_FAULT = 0x0001

SensorFaultBitmap.mask_fields = {
  BASE_MASK = 0xFFFF,
  GENERAL_FAULT = 0x0001,
}

SensorFaultBitmap.is_general_fault_set = function(self)
  return (self.value & self.GENERAL_FAULT) ~= 0
end

SensorFaultBitmap.set_general_fault = function(self)
  if self.value ~= nil then
    self.value = self.value | self.GENERAL_FAULT
  else
    self.value = self.GENERAL_FAULT
  end
end

SensorFaultBitmap.unset_general_fault = function(self)
  self.value = self.value & (~self.GENERAL_FAULT & self.BASE_MASK)
end


SensorFaultBitmap.mask_methods = {
  is_general_fault_set = SensorFaultBitmap.is_general_fault_set,
  set_general_fault = SensorFaultBitmap.set_general_fault,
  unset_general_fault = SensorFaultBitmap.unset_general_fault,
}

SensorFaultBitmap.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(SensorFaultBitmap, new_mt)

return SensorFaultBitmap
