local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local DlLocalProgrammingFeatures = {}
local new_mt = UintABC.new_mt({NAME = "DlLocalProgrammingFeatures", ID = data_types.name_to_id_map["Uint8"]}, 1)

DlLocalProgrammingFeatures.BASE_MASK = 0xFFFF
DlLocalProgrammingFeatures.ADD_USERS_CREDENTIALS_SCHEDULES_LOCALLY = 0x0001
DlLocalProgrammingFeatures.MODIFY_USERS_CREDENTIALS_SCHEDULES_LOCALLY = 0x0002
DlLocalProgrammingFeatures.CLEAR_USERS_CREDENTIALS_SCHEDULES_LOCALLY = 0x0004
DlLocalProgrammingFeatures.ADJUST_LOCK_SETTINGS_LOCALLY = 0x0008

DlLocalProgrammingFeatures.mask_fields = {
  BASE_MASK = 0xFFFF,
  ADD_USERS_CREDENTIALS_SCHEDULES_LOCALLY = 0x0001,
  MODIFY_USERS_CREDENTIALS_SCHEDULES_LOCALLY = 0x0002,
  CLEAR_USERS_CREDENTIALS_SCHEDULES_LOCALLY = 0x0004,
  ADJUST_LOCK_SETTINGS_LOCALLY = 0x0008,
}

DlLocalProgrammingFeatures.is_add_users_credentials_schedules_locally_set = function(self)
  return (self.value & self.ADD_USERS_CREDENTIALS_SCHEDULES_LOCALLY) ~= 0
end

DlLocalProgrammingFeatures.set_add_users_credentials_schedules_locally = function(self)
  if self.value ~= nil then
    self.value = self.value | self.ADD_USERS_CREDENTIALS_SCHEDULES_LOCALLY
  else
    self.value = self.ADD_USERS_CREDENTIALS_SCHEDULES_LOCALLY
  end
end

DlLocalProgrammingFeatures.unset_add_users_credentials_schedules_locally = function(self)
  self.value = self.value & (~self.ADD_USERS_CREDENTIALS_SCHEDULES_LOCALLY & self.BASE_MASK)
end

DlLocalProgrammingFeatures.is_modify_users_credentials_schedules_locally_set = function(self)
  return (self.value & self.MODIFY_USERS_CREDENTIALS_SCHEDULES_LOCALLY) ~= 0
end

DlLocalProgrammingFeatures.set_modify_users_credentials_schedules_locally = function(self)
  if self.value ~= nil then
    self.value = self.value | self.MODIFY_USERS_CREDENTIALS_SCHEDULES_LOCALLY
  else
    self.value = self.MODIFY_USERS_CREDENTIALS_SCHEDULES_LOCALLY
  end
end

DlLocalProgrammingFeatures.unset_modify_users_credentials_schedules_locally = function(self)
  self.value = self.value & (~self.MODIFY_USERS_CREDENTIALS_SCHEDULES_LOCALLY & self.BASE_MASK)
end

DlLocalProgrammingFeatures.is_clear_users_credentials_schedules_locally_set = function(self)
  return (self.value & self.CLEAR_USERS_CREDENTIALS_SCHEDULES_LOCALLY) ~= 0
end

DlLocalProgrammingFeatures.set_clear_users_credentials_schedules_locally = function(self)
  if self.value ~= nil then
    self.value = self.value | self.CLEAR_USERS_CREDENTIALS_SCHEDULES_LOCALLY
  else
    self.value = self.CLEAR_USERS_CREDENTIALS_SCHEDULES_LOCALLY
  end
end

DlLocalProgrammingFeatures.unset_clear_users_credentials_schedules_locally = function(self)
  self.value = self.value & (~self.CLEAR_USERS_CREDENTIALS_SCHEDULES_LOCALLY & self.BASE_MASK)
end

DlLocalProgrammingFeatures.is_adjust_lock_settings_locally_set = function(self)
  return (self.value & self.ADJUST_LOCK_SETTINGS_LOCALLY) ~= 0
end

DlLocalProgrammingFeatures.set_adjust_lock_settings_locally = function(self)
  if self.value ~= nil then
    self.value = self.value | self.ADJUST_LOCK_SETTINGS_LOCALLY
  else
    self.value = self.ADJUST_LOCK_SETTINGS_LOCALLY
  end
end

DlLocalProgrammingFeatures.unset_adjust_lock_settings_locally = function(self)
  self.value = self.value & (~self.ADJUST_LOCK_SETTINGS_LOCALLY & self.BASE_MASK)
end

DlLocalProgrammingFeatures.mask_methods = {
  is_add_users_credentials_schedules_locally_set = DlLocalProgrammingFeatures.is_add_users_credentials_schedules_locally_set,
  set_add_users_credentials_schedules_locally = DlLocalProgrammingFeatures.set_add_users_credentials_schedules_locally,
  unset_add_users_credentials_schedules_locally = DlLocalProgrammingFeatures.unset_add_users_credentials_schedules_locally,
  is_modify_users_credentials_schedules_locally_set = DlLocalProgrammingFeatures.is_modify_users_credentials_schedules_locally_set,
  set_modify_users_credentials_schedules_locally = DlLocalProgrammingFeatures.set_modify_users_credentials_schedules_locally,
  unset_modify_users_credentials_schedules_locally = DlLocalProgrammingFeatures.unset_modify_users_credentials_schedules_locally,
  is_clear_users_credentials_schedules_locally_set = DlLocalProgrammingFeatures.is_clear_users_credentials_schedules_locally_set,
  set_clear_users_credentials_schedules_locally = DlLocalProgrammingFeatures.set_clear_users_credentials_schedules_locally,
  unset_clear_users_credentials_schedules_locally = DlLocalProgrammingFeatures.unset_clear_users_credentials_schedules_locally,
  is_adjust_lock_settings_locally_set = DlLocalProgrammingFeatures.is_adjust_lock_settings_locally_set,
  set_adjust_lock_settings_locally = DlLocalProgrammingFeatures.set_adjust_lock_settings_locally,
  unset_adjust_lock_settings_locally = DlLocalProgrammingFeatures.unset_adjust_lock_settings_locally,
}

DlLocalProgrammingFeatures.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(DlLocalProgrammingFeatures, new_mt)

return DlLocalProgrammingFeatures