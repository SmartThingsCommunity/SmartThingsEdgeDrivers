local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local Feature = {}
local new_mt = UintABC.new_mt({NAME = "Feature", ID = data_types.name_to_id_map["Uint32"]}, 4)

Feature.BASE_MASK = 0xFFFF
Feature.CHARGING_PREFERENCES = 0x0001
Feature.SOC_REPORTING = 0x0002
Feature.PLUG_AND_CHARGE = 0x0004
Feature.RFID = 0x0008
Feature.V2X = 0x0010

Feature.mask_fields = {
  BASE_MASK = 0xFFFF,
  CHARGING_PREFERENCES = 0x0001,
  SOC_REPORTING = 0x0002,
  PLUG_AND_CHARGE = 0x0004,
  RFID = 0x0008,
  V2X = 0x0010,
}

Feature.is_charging_preferences_set = function(self)
  return (self.value & self.CHARGING_PREFERENCES) ~= 0
end

Feature.set_charging_preferences = function(self)
  if self.value ~= nil then
    self.value = self.value | self.CHARGING_PREFERENCES
  else
    self.value = self.CHARGING_PREFERENCES
  end
end

Feature.unset_charging_preferences = function(self)
  self.value = self.value & (~self.CHARGING_PREFERENCES & self.BASE_MASK)
end

Feature.is_soc_reporting_set = function(self)
  return (self.value & self.SOC_REPORTING) ~= 0
end

Feature.set_soc_reporting = function(self)
  if self.value ~= nil then
    self.value = self.value | self.SOC_REPORTING
  else
    self.value = self.SOC_REPORTING
  end
end

Feature.unset_soc_reporting = function(self)
  self.value = self.value & (~self.SOC_REPORTING & self.BASE_MASK)
end

Feature.is_plug_and_charge_set = function(self)
  return (self.value & self.PLUG_AND_CHARGE) ~= 0
end

Feature.set_plug_and_charge = function(self)
  if self.value ~= nil then
    self.value = self.value | self.PLUG_AND_CHARGE
  else
    self.value = self.PLUG_AND_CHARGE
  end
end

Feature.unset_plug_and_charge = function(self)
  self.value = self.value & (~self.PLUG_AND_CHARGE & self.BASE_MASK)
end

Feature.is_rfid_set = function(self)
  return (self.value & self.RFID) ~= 0
end

Feature.set_rfid = function(self)
  if self.value ~= nil then
    self.value = self.value | self.RFID
  else
    self.value = self.RFID
  end
end

Feature.unset_rfid = function(self)
  self.value = self.value & (~self.RFID & self.BASE_MASK)
end

Feature.is_v2x_set = function(self)
  return (self.value & self.V2X) ~= 0
end

Feature.set_v2x = function(self)
  if self.value ~= nil then
    self.value = self.value | self.V2X
  else
    self.value = self.V2X
  end
end

Feature.unset_v2x = function(self)
  self.value = self.value & (~self.V2X & self.BASE_MASK)
end

function Feature.bits_are_valid(feature)
  local max =
      Feature.CHARGING_PREFERENCES | Feature.SOC_REPORTING | Feature.PLUG_AND_CHARGE | Feature.RFID | Feature.V2X
  if (feature <= max) and (feature >= 1) then
    return true
  else
    return false
  end
end

Feature.mask_methods = {
  is_charging_preferences_set = Feature.is_charging_preferences_set,
  set_charging_preferences = Feature.set_charging_preferences,
  unset_charging_preferences = Feature.unset_charging_preferences,
  is_soc_reporting_set = Feature.is_soc_reporting_set,
  set_soc_reporting = Feature.set_soc_reporting,
  unset_soc_reporting = Feature.unset_soc_reporting,
  is_plug_and_charge_set = Feature.is_plug_and_charge_set,
  set_plug_and_charge = Feature.set_plug_and_charge,
  unset_plug_and_charge = Feature.unset_plug_and_charge,
  is_rfid_set = Feature.is_rfid_set,
  set_rfid = Feature.set_rfid,
  unset_rfid = Feature.unset_rfid,
  is_v2x_set = Feature.is_v2x_set,
  set_v2x = Feature.set_v2x,
  unset_v2x = Feature.unset_v2x,
}

Feature.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(Feature, new_mt)

return Feature

