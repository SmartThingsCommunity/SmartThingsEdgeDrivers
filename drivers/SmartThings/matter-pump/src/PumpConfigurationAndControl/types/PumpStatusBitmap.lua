local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local PumpStatusBitmap = {}
local new_mt = UintABC.new_mt({NAME = "PumpStatusBitmap", ID = data_types.name_to_id_map["Uint16"]}, 2)

PumpStatusBitmap.BASE_MASK = 0xFFFF
PumpStatusBitmap.DEVICE_FAULT = 0x0001
PumpStatusBitmap.SUPPLYFAULT = 0x0002
PumpStatusBitmap.SPEED_LOW = 0x0004
PumpStatusBitmap.SPEED_HIGH = 0x0008
PumpStatusBitmap.LOCAL_OVERRIDE = 0x0010
PumpStatusBitmap.RUNNING = 0x0020
PumpStatusBitmap.REMOTE_PRESSURE = 0x0040
PumpStatusBitmap.REMOTE_FLOW = 0x0080
PumpStatusBitmap.REMOTE_TEMPERATURE = 0x0100

PumpStatusBitmap.mask_fields = {
  BASE_MASK = 0xFFFF,
  DEVICE_FAULT = 0x0001,
  SUPPLYFAULT = 0x0002,
  SPEED_LOW = 0x0004,
  SPEED_HIGH = 0x0008,
  LOCAL_OVERRIDE = 0x0010,
  RUNNING = 0x0020,
  REMOTE_PRESSURE = 0x0040,
  REMOTE_FLOW = 0x0080,
  REMOTE_TEMPERATURE = 0x0100,
}

PumpStatusBitmap.is_device_fault_set = function(self)
  return (self.value & self.DEVICE_FAULT) ~= 0
end

PumpStatusBitmap.set_device_fault = function(self)
  if self.value ~= nil then
    self.value = self.value | self.DEVICE_FAULT
  else
    self.value = self.DEVICE_FAULT
  end
end

PumpStatusBitmap.unset_device_fault = function(self)
  self.value = self.value & (~self.DEVICE_FAULT & self.BASE_MASK)
end

PumpStatusBitmap.is_supplyfault_set = function(self)
  return (self.value & self.SUPPLYFAULT) ~= 0
end

PumpStatusBitmap.set_supplyfault = function(self)
  if self.value ~= nil then
    self.value = self.value | self.SUPPLYFAULT
  else
    self.value = self.SUPPLYFAULT
  end
end

PumpStatusBitmap.unset_supplyfault = function(self)
  self.value = self.value & (~self.SUPPLYFAULT & self.BASE_MASK)
end

PumpStatusBitmap.is_speed_low_set = function(self)
  return (self.value & self.SPEED_LOW) ~= 0
end

PumpStatusBitmap.set_speed_low = function(self)
  if self.value ~= nil then
    self.value = self.value | self.SPEED_LOW
  else
    self.value = self.SPEED_LOW
  end
end

PumpStatusBitmap.unset_speed_low = function(self)
  self.value = self.value & (~self.SPEED_LOW & self.BASE_MASK)
end

PumpStatusBitmap.is_speed_high_set = function(self)
  return (self.value & self.SPEED_HIGH) ~= 0
end

PumpStatusBitmap.set_speed_high = function(self)
  if self.value ~= nil then
    self.value = self.value | self.SPEED_HIGH
  else
    self.value = self.SPEED_HIGH
  end
end

PumpStatusBitmap.unset_speed_high = function(self)
  self.value = self.value & (~self.SPEED_HIGH & self.BASE_MASK)
end

PumpStatusBitmap.is_local_override_set = function(self)
  return (self.value & self.LOCAL_OVERRIDE) ~= 0
end

PumpStatusBitmap.set_local_override = function(self)
  if self.value ~= nil then
    self.value = self.value | self.LOCAL_OVERRIDE
  else
    self.value = self.LOCAL_OVERRIDE
  end
end

PumpStatusBitmap.unset_local_override = function(self)
  self.value = self.value & (~self.LOCAL_OVERRIDE & self.BASE_MASK)
end

PumpStatusBitmap.is_running_set = function(self)
  return (self.value & self.RUNNING) ~= 0
end

PumpStatusBitmap.set_running = function(self)
  if self.value ~= nil then
    self.value = self.value | self.RUNNING
  else
    self.value = self.RUNNING
  end
end

PumpStatusBitmap.unset_running = function(self)
  self.value = self.value & (~self.RUNNING & self.BASE_MASK)
end

PumpStatusBitmap.is_remote_pressure_set = function(self)
  return (self.value & self.REMOTE_PRESSURE) ~= 0
end

PumpStatusBitmap.set_remote_pressure = function(self)
  if self.value ~= nil then
    self.value = self.value | self.REMOTE_PRESSURE
  else
    self.value = self.REMOTE_PRESSURE
  end
end

PumpStatusBitmap.unset_remote_pressure = function(self)
  self.value = self.value & (~self.REMOTE_PRESSURE & self.BASE_MASK)
end

PumpStatusBitmap.is_remote_flow_set = function(self)
  return (self.value & self.REMOTE_FLOW) ~= 0
end

PumpStatusBitmap.set_remote_flow = function(self)
  if self.value ~= nil then
    self.value = self.value | self.REMOTE_FLOW
  else
    self.value = self.REMOTE_FLOW
  end
end

PumpStatusBitmap.unset_remote_flow = function(self)
  self.value = self.value & (~self.REMOTE_FLOW & self.BASE_MASK)
end

PumpStatusBitmap.is_remote_temperature_set = function(self)
  return (self.value & self.REMOTE_TEMPERATURE) ~= 0
end

PumpStatusBitmap.set_remote_temperature = function(self)
  if self.value ~= nil then
    self.value = self.value | self.REMOTE_TEMPERATURE
  else
    self.value = self.REMOTE_TEMPERATURE
  end
end

PumpStatusBitmap.unset_remote_temperature = function(self)
  self.value = self.value & (~self.REMOTE_TEMPERATURE & self.BASE_MASK)
end

PumpStatusBitmap.mask_methods = {
  is_device_fault_set = PumpStatusBitmap.is_device_fault_set,
  set_device_fault = PumpStatusBitmap.set_device_fault,
  unset_device_fault = PumpStatusBitmap.unset_device_fault,
  is_supplyfault_set = PumpStatusBitmap.is_supplyfault_set,
  set_supplyfault = PumpStatusBitmap.set_supplyfault,
  unset_supplyfault = PumpStatusBitmap.unset_supplyfault,
  is_speed_low_set = PumpStatusBitmap.is_speed_low_set,
  set_speed_low = PumpStatusBitmap.set_speed_low,
  unset_speed_low = PumpStatusBitmap.unset_speed_low,
  is_speed_high_set = PumpStatusBitmap.is_speed_high_set,
  set_speed_high = PumpStatusBitmap.set_speed_high,
  unset_speed_high = PumpStatusBitmap.unset_speed_high,
  is_local_override_set = PumpStatusBitmap.is_local_override_set,
  set_local_override = PumpStatusBitmap.set_local_override,
  unset_local_override = PumpStatusBitmap.unset_local_override,
  is_running_set = PumpStatusBitmap.is_running_set,
  set_running = PumpStatusBitmap.set_running,
  unset_running = PumpStatusBitmap.unset_running,
  is_remote_pressure_set = PumpStatusBitmap.is_remote_pressure_set,
  set_remote_pressure = PumpStatusBitmap.set_remote_pressure,
  unset_remote_pressure = PumpStatusBitmap.unset_remote_pressure,
  is_remote_flow_set = PumpStatusBitmap.is_remote_flow_set,
  set_remote_flow = PumpStatusBitmap.set_remote_flow,
  unset_remote_flow = PumpStatusBitmap.unset_remote_flow,
  is_remote_temperature_set = PumpStatusBitmap.is_remote_temperature_set,
  set_remote_temperature = PumpStatusBitmap.set_remote_temperature,
  unset_remote_temperature = PumpStatusBitmap.unset_remote_temperature,
}

PumpStatusBitmap.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(PumpStatusBitmap, new_mt)

return PumpStatusBitmap
