local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local Feature = {}
local new_mt = UintABC.new_mt({NAME = "Feature", ID = data_types.name_to_id_map["Uint32"]}, 4)

Feature.BASE_MASK = 0xFFFF
Feature.SMOKE_ALARM = 0x0001
Feature.CO_ALARM = 0x0002

Feature.mask_fields = {
  BASE_MASK = 0xFFFF,
  SMOKE_ALARM = 0x0001,
  CO_ALARM = 0x0002,
}

Feature.is_smoke_alarm_set = function(self)
  return (self.value & self.SMOKE_ALARM) ~= 0
end

Feature.set_smoke_alarm = function(self)
  if self.value ~= nil then
    self.value = self.value | self.SMOKE_ALARM
  else
    self.value = self.SMOKE_ALARM
  end
end

Feature.unset_smoke_alarm = function(self)
  self.value = self.value & (~self.SMOKE_ALARM & self.BASE_MASK)
end

Feature.is_co_alarm_set = function(self)
  return (self.value & self.CO_ALARM) ~= 0
end

Feature.set_co_alarm = function(self)
  if self.value ~= nil then
    self.value = self.value | self.CO_ALARM
  else
    self.value = self.CO_ALARM
  end
end

Feature.unset_co_alarm = function(self)
  self.value = self.value & (~self.CO_ALARM & self.BASE_MASK)
end

function Feature.bits_are_valid(feature)
  local max =
    Feature.SMOKE_ALARM |
    Feature.CO_ALARM
  if (feature <= max) and (feature >= 1) then
    return true
  else
    return false
  end
end

Feature.mask_methods = {
  is_smoke_alarm_set = Feature.is_smoke_alarm_set,
  set_smoke_alarm = Feature.set_smoke_alarm,
  unset_smoke_alarm = Feature.unset_smoke_alarm,
  is_co_alarm_set = Feature.is_co_alarm_set,
  set_co_alarm = Feature.set_co_alarm,
  unset_co_alarm = Feature.unset_co_alarm,
}

Feature.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(Feature, new_mt)

return Feature

