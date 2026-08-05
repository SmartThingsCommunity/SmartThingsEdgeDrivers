local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local AlarmMap = {}
-- Note: the name here is intentionally set to Uint32 to maintain backwards compatibility
-- with how types were handled in api < 10.
local new_mt = UintABC.new_mt({NAME = "Uint32", ID = data_types.name_to_id_map["Uint32"]}, 4)

AlarmMap.BASE_MASK = 0xFFFF
AlarmMap.DOOR_OPEN = 0x0001

AlarmMap.mask_fields = {
  BASE_MASK = 0xFFFF,
  DOOR_OPEN = 0x0001,
}

AlarmMap.is_door_open_set = function(self)
  return (self.value & self.DOOR_OPEN) ~= 0
end

AlarmMap.set_door_open = function(self)
  if self.value ~= nil then
    self.value = self.value | self.DOOR_OPEN
  else
    self.value = self.DOOR_OPEN
  end
end

AlarmMap.unset_door_open = function(self)
  self.value = self.value & (~self.DOOR_OPEN & self.BASE_MASK)
end


AlarmMap.mask_methods = {
  is_door_open_set = AlarmMap.is_door_open_set,
  set_door_open = AlarmMap.set_door_open,
  unset_door_open = AlarmMap.unset_door_open,
}

AlarmMap.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(AlarmMap, new_mt)

return AlarmMap

