local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local AlarmMap = {}
local new_mt = UintABC.new_mt({NAME = "AlarmMap", ID = data_types.name_to_id_map["Uint32"]}, 4)

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

local has_aliases, aliases = pcall(require, "st.matter.clusters.aliases.RefrigeratorAlarm.types.AlarmMap")
if has_aliases then
  aliases:add_to_class(AlarmMap)
end

return AlarmMap

