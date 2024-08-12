local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"
local ValveFaultBitmap = {}
local new_mt = UintABC.new_mt({NAME = "ValveFaultBitmap", ID = data_types.name_to_id_map["Uint16"]}, 2)

ValveFaultBitmap.BASE_MASK = 0xFFFF
ValveFaultBitmap.GENERAL_FAULT = 0x0001
ValveFaultBitmap.BLOCKED = 0x0002
ValveFaultBitmap.LEAKING = 0x0004
ValveFaultBitmap.NOT_CONNECTED = 0x0008
ValveFaultBitmap.SHORT_CIRCUIT = 0x0010
ValveFaultBitmap.CURRENT_EXCEEDED = 0x0020

ValveFaultBitmap.mask_fields = {
  BASE_MASK = 0xFFFF,
  GENERAL_FAULT = 0x0001,
  BLOCKED = 0x0002,
  LEAKING = 0x0004,
  NOT_CONNECTED = 0x0008,
  SHORT_CIRCUIT = 0x0010,
  CURRENT_EXCEEDED = 0x0020,
}

ValveFaultBitmap.is_general_fault_set = function(self)
  return (self.value & self.GENERAL_FAULT) ~= 0
end

ValveFaultBitmap.set_general_fault = function(self)
  if self.value ~= nil then
    self.value = self.value | self.GENERAL_FAULT
  else
    self.value = self.GENERAL_FAULT
  end
end

ValveFaultBitmap.unset_general_fault = function(self)
  self.value = self.value & (~self.GENERAL_FAULT & self.BASE_MASK)
end

ValveFaultBitmap.is_blocked_set = function(self)
  return (self.value & self.BLOCKED) ~= 0
end

ValveFaultBitmap.set_blocked = function(self)
  if self.value ~= nil then
    self.value = self.value | self.BLOCKED
  else
    self.value = self.BLOCKED
  end
end

ValveFaultBitmap.unset_blocked = function(self)
  self.value = self.value & (~self.BLOCKED & self.BASE_MASK)
end

ValveFaultBitmap.is_leaking_set = function(self)
  return (self.value & self.LEAKING) ~= 0
end

ValveFaultBitmap.set_leaking = function(self)
  if self.value ~= nil then
    self.value = self.value | self.LEAKING
  else
    self.value = self.LEAKING
  end
end

ValveFaultBitmap.unset_leaking = function(self)
  self.value = self.value & (~self.LEAKING & self.BASE_MASK)
end

ValveFaultBitmap.is_not_connected_set = function(self)
  return (self.value & self.NOT_CONNECTED) ~= 0
end

ValveFaultBitmap.set_not_connected = function(self)
  if self.value ~= nil then
    self.value = self.value | self.NOT_CONNECTED
  else
    self.value = self.NOT_CONNECTED
  end
end

ValveFaultBitmap.unset_not_connected = function(self)
  self.value = self.value & (~self.NOT_CONNECTED & self.BASE_MASK)
end

ValveFaultBitmap.is_short_circuit_set = function(self)
  return (self.value & self.SHORT_CIRCUIT) ~= 0
end

ValveFaultBitmap.set_short_circuit = function(self)
  if self.value ~= nil then
    self.value = self.value | self.SHORT_CIRCUIT
  else
    self.value = self.SHORT_CIRCUIT
  end
end

ValveFaultBitmap.unset_short_circuit = function(self)
  self.value = self.value & (~self.SHORT_CIRCUIT & self.BASE_MASK)
end

ValveFaultBitmap.is_current_exceeded_set = function(self)
  return (self.value & self.CURRENT_EXCEEDED) ~= 0
end

ValveFaultBitmap.set_current_exceeded = function(self)
  if self.value ~= nil then
    self.value = self.value | self.CURRENT_EXCEEDED
  else
    self.value = self.CURRENT_EXCEEDED
  end
end

ValveFaultBitmap.unset_current_exceeded = function(self)
  self.value = self.value & (~self.CURRENT_EXCEEDED & self.BASE_MASK)
end

ValveFaultBitmap.mask_methods = {
  is_general_fault_set = ValveFaultBitmap.is_general_fault_set,
  set_general_fault = ValveFaultBitmap.set_general_fault,
  unset_general_fault = ValveFaultBitmap.unset_general_fault,
  is_blocked_set = ValveFaultBitmap.is_blocked_set,
  set_blocked = ValveFaultBitmap.set_blocked,
  unset_blocked = ValveFaultBitmap.unset_blocked,
  is_leaking_set = ValveFaultBitmap.is_leaking_set,
  set_leaking = ValveFaultBitmap.set_leaking,
  unset_leaking = ValveFaultBitmap.unset_leaking,
  is_not_connected_set = ValveFaultBitmap.is_not_connected_set,
  set_not_connected = ValveFaultBitmap.set_not_connected,
  unset_not_connected = ValveFaultBitmap.unset_not_connected,
  is_short_circuit_set = ValveFaultBitmap.is_short_circuit_set,
  set_short_circuit = ValveFaultBitmap.set_short_circuit,
  unset_short_circuit = ValveFaultBitmap.unset_short_circuit,
  is_current_exceeded_set = ValveFaultBitmap.is_current_exceeded_set,
  set_current_exceeded = ValveFaultBitmap.set_current_exceeded,
  unset_current_exceeded = ValveFaultBitmap.unset_current_exceeded,
}

ValveFaultBitmap.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(ValveFaultBitmap, new_mt)

local has_aliases, aliases = pcall(require, "st.matter.clusters.aliases.ValveConfigurationAndControl.types.ValveFaultBitmap")
if has_aliases then
  aliases:add_to_class(ValveFaultBitmap)
end

return ValveFaultBitmap
