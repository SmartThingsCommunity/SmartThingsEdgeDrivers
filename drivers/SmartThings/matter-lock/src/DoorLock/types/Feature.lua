local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local Feature = {}
local new_mt = UintABC.new_mt({NAME = "Feature", ID = data_types.name_to_id_map["Uint32"]}, 4)

Feature.BASE_MASK = 0xFFFF
Feature.PIN_CREDENTIAL = 0x0001
Feature.RFID_CREDENTIAL = 0x0002
Feature.FINGER_CREDENTIALS = 0x0004
Feature.LOGGING = 0x0008
Feature.WEEK_DAY_ACCESS_SCHEDULES = 0x0010
Feature.DOOR_POSITION_SENSOR = 0x0020
Feature.FACE_CREDENTIALS = 0x0040
Feature.CREDENTIALS_OVER_THE_AIR_ACCESS = 0x0080
Feature.USER = 0x0100
Feature.NOTIFICATION = 0x0200
Feature.YEAR_DAY_ACCESS_SCHEDULES = 0x0400
Feature.HOLIDAY_SCHEDULES = 0x0800
Feature.UNBOLT = 0x1000
Feature.ALIRO_PROVISIONING = 0x2000
Feature.ALIROBLEUWB = 0x4000

Feature.mask_fields = {
  BASE_MASK = 0xFFFF,
  PIN_CREDENTIAL = 0x0001,
  RFID_CREDENTIAL = 0x0002,
  FINGER_CREDENTIALS = 0x0004,
  LOGGING = 0x0008,
  WEEK_DAY_ACCESS_SCHEDULES = 0x0010,
  DOOR_POSITION_SENSOR = 0x0020,
  FACE_CREDENTIALS = 0x0040,
  CREDENTIALS_OVER_THE_AIR_ACCESS = 0x0080,
  USER = 0x0100,
  NOTIFICATION = 0x0200,
  YEAR_DAY_ACCESS_SCHEDULES = 0x0400,
  HOLIDAY_SCHEDULES = 0x0800,
  UNBOLT = 0x1000,
  ALIRO_PROVISIONING = 0x2000,
  ALIROBLEUWB = 0x4000,
}

Feature.is_pin_credential_set = function(self)
  return (self.value & self.PIN_CREDENTIAL) ~= 0
end

Feature.set_pin_credential = function(self)
  if self.value ~= nil then
    self.value = self.value | self.PIN_CREDENTIAL
  else
    self.value = self.PIN_CREDENTIAL
  end
end

Feature.unset_pin_credential = function(self)
  self.value = self.value & (~self.PIN_CREDENTIAL & self.BASE_MASK)
end

Feature.is_rfid_credential_set = function(self)
  return (self.value & self.RFID_CREDENTIAL) ~= 0
end

Feature.set_rfid_credential = function(self)
  if self.value ~= nil then
    self.value = self.value | self.RFID_CREDENTIAL
  else
    self.value = self.RFID_CREDENTIAL
  end
end

Feature.unset_rfid_credential = function(self)
  self.value = self.value & (~self.RFID_CREDENTIAL & self.BASE_MASK)
end

Feature.is_finger_credentials_set = function(self)
  return (self.value & self.FINGER_CREDENTIALS) ~= 0
end

Feature.set_finger_credentials = function(self)
  if self.value ~= nil then
    self.value = self.value | self.FINGER_CREDENTIALS
  else
    self.value = self.FINGER_CREDENTIALS
  end
end

Feature.unset_finger_credentials = function(self)
  self.value = self.value & (~self.FINGER_CREDENTIALS & self.BASE_MASK)
end

Feature.is_logging_set = function(self)
  return (self.value & self.LOGGING) ~= 0
end

Feature.set_logging = function(self)
  if self.value ~= nil then
    self.value = self.value | self.LOGGING
  else
    self.value = self.LOGGING
  end
end

Feature.unset_logging = function(self)
  self.value = self.value & (~self.LOGGING & self.BASE_MASK)
end

Feature.is_week_day_access_schedules_set = function(self)
  return (self.value & self.WEEK_DAY_ACCESS_SCHEDULES) ~= 0
end

Feature.set_week_day_access_schedules = function(self)
  if self.value ~= nil then
    self.value = self.value | self.WEEK_DAY_ACCESS_SCHEDULES
  else
    self.value = self.WEEK_DAY_ACCESS_SCHEDULES
  end
end

Feature.unset_week_day_access_schedules = function(self)
  self.value = self.value & (~self.WEEK_DAY_ACCESS_SCHEDULES & self.BASE_MASK)
end

Feature.is_door_position_sensor_set = function(self)
  return (self.value & self.DOOR_POSITION_SENSOR) ~= 0
end

Feature.set_door_position_sensor = function(self)
  if self.value ~= nil then
    self.value = self.value | self.DOOR_POSITION_SENSOR
  else
    self.value = self.DOOR_POSITION_SENSOR
  end
end

Feature.unset_door_position_sensor = function(self)
  self.value = self.value & (~self.DOOR_POSITION_SENSOR & self.BASE_MASK)
end

Feature.is_face_credentials_set = function(self)
  return (self.value & self.FACE_CREDENTIALS) ~= 0
end

Feature.set_face_credentials = function(self)
  if self.value ~= nil then
    self.value = self.value | self.FACE_CREDENTIALS
  else
    self.value = self.FACE_CREDENTIALS
  end
end

Feature.unset_face_credentials = function(self)
  self.value = self.value & (~self.FACE_CREDENTIALS & self.BASE_MASK)
end

Feature.is_credentials_over_the_air_access_set = function(self)
  return (self.value & self.CREDENTIALS_OVER_THE_AIR_ACCESS) ~= 0
end

Feature.set_credentials_over_the_air_access = function(self)
  if self.value ~= nil then
    self.value = self.value | self.CREDENTIALS_OVER_THE_AIR_ACCESS
  else
    self.value = self.CREDENTIALS_OVER_THE_AIR_ACCESS
  end
end

Feature.unset_credentials_over_the_air_access = function(self)
  self.value = self.value & (~self.CREDENTIALS_OVER_THE_AIR_ACCESS & self.BASE_MASK)
end

Feature.is_user_set = function(self)
  return (self.value & self.USER) ~= 0
end

Feature.set_user = function(self)
  if self.value ~= nil then
    self.value = self.value | self.USER
  else
    self.value = self.USER
  end
end

Feature.unset_user = function(self)
  self.value = self.value & (~self.USER & self.BASE_MASK)
end

Feature.is_notification_set = function(self)
  return (self.value & self.NOTIFICATION) ~= 0
end

Feature.set_notification = function(self)
  if self.value ~= nil then
    self.value = self.value | self.NOTIFICATION
  else
    self.value = self.NOTIFICATION
  end
end

Feature.unset_notification = function(self)
  self.value = self.value & (~self.NOTIFICATION & self.BASE_MASK)
end

Feature.is_year_day_access_schedules_set = function(self)
  return (self.value & self.YEAR_DAY_ACCESS_SCHEDULES) ~= 0
end

Feature.set_year_day_access_schedules = function(self)
  if self.value ~= nil then
    self.value = self.value | self.YEAR_DAY_ACCESS_SCHEDULES
  else
    self.value = self.YEAR_DAY_ACCESS_SCHEDULES
  end
end

Feature.unset_year_day_access_schedules = function(self)
  self.value = self.value & (~self.YEAR_DAY_ACCESS_SCHEDULES & self.BASE_MASK)
end

Feature.is_holiday_schedules_set = function(self)
  return (self.value & self.HOLIDAY_SCHEDULES) ~= 0
end

Feature.set_holiday_schedules = function(self)
  if self.value ~= nil then
    self.value = self.value | self.HOLIDAY_SCHEDULES
  else
    self.value = self.HOLIDAY_SCHEDULES
  end
end

Feature.unset_holiday_schedules = function(self)
  self.value = self.value & (~self.HOLIDAY_SCHEDULES & self.BASE_MASK)
end

Feature.is_unbolt_set = function(self)
  return (self.value & self.UNBOLT) ~= 0
end

Feature.set_unbolt = function(self)
  if self.value ~= nil then
    self.value = self.value | self.UNBOLT
  else
    self.value = self.UNBOLT
  end
end

Feature.unset_unbolt = function(self)
  self.value = self.value & (~self.UNBOLT & self.BASE_MASK)
end

Feature.is_aliro_provisioning_set = function(self)
  return (self.value & self.ALIRO_PROVISIONING) ~= 0
end

Feature.set_aliro_provisioning = function(self)
  if self.value ~= nil then
    self.value = self.value | self.ALIRO_PROVISIONING
  else
    self.value = self.ALIRO_PROVISIONING
  end
end

Feature.unset_aliro_provisioning = function(self)
  self.value = self.value & (~self.ALIRO_PROVISIONING & self.BASE_MASK)
end

Feature.is_alirobleuwb_set = function(self)
  return (self.value & self.ALIROBLEUWB) ~= 0
end

Feature.set_alirobleuwb = function(self)
  if self.value ~= nil then
    self.value = self.value | self.ALIROBLEUWB
  else
    self.value = self.ALIROBLEUWB
  end
end

Feature.unset_alirobleuwb = function(self)
  self.value = self.value & (~self.ALIROBLEUWB & self.BASE_MASK)
end

function Feature.bits_are_valid(feature)
  local max =
    Feature.PIN_CREDENTIAL |
    Feature.RFID_CREDENTIAL |
    Feature.FINGER_CREDENTIALS |
    Feature.LOGGING |
    Feature.WEEK_DAY_ACCESS_SCHEDULES |
    Feature.DOOR_POSITION_SENSOR |
    Feature.FACE_CREDENTIALS |
    Feature.CREDENTIALS_OVER_THE_AIR_ACCESS |
    Feature.USER |
    Feature.NOTIFICATION |
    Feature.YEAR_DAY_ACCESS_SCHEDULES |
    Feature.HOLIDAY_SCHEDULES |
    Feature.UNBOLT |
    Feature.ALIRO_PROVISIONING |
    Feature.ALIROBLEUWB
  if (feature <= max) and (feature >= 1) then
    return true
  else
    return false
  end
end

Feature.mask_methods = {
  is_pin_credential_set = Feature.is_pin_credential_set,
  set_pin_credential = Feature.set_pin_credential,
  unset_pin_credential = Feature.unset_pin_credential,
  is_rfid_credential_set = Feature.is_rfid_credential_set,
  set_rfid_credential = Feature.set_rfid_credential,
  unset_rfid_credential = Feature.unset_rfid_credential,
  is_finger_credentials_set = Feature.is_finger_credentials_set,
  set_finger_credentials = Feature.set_finger_credentials,
  unset_finger_credentials = Feature.unset_finger_credentials,
  is_logging_set = Feature.is_logging_set,
  set_logging = Feature.set_logging,
  unset_logging = Feature.unset_logging,
  is_week_day_access_schedules_set = Feature.is_week_day_access_schedules_set,
  set_week_day_access_schedules = Feature.set_week_day_access_schedules,
  unset_week_day_access_schedules = Feature.unset_week_day_access_schedules,
  is_door_position_sensor_set = Feature.is_door_position_sensor_set,
  set_door_position_sensor = Feature.set_door_position_sensor,
  unset_door_position_sensor = Feature.unset_door_position_sensor,
  is_face_credentials_set = Feature.is_face_credentials_set,
  set_face_credentials = Feature.set_face_credentials,
  unset_face_credentials = Feature.unset_face_credentials,
  is_credentials_over_the_air_access_set = Feature.is_credentials_over_the_air_access_set,
  set_credentials_over_the_air_access = Feature.set_credentials_over_the_air_access,
  unset_credentials_over_the_air_access = Feature.unset_credentials_over_the_air_access,
  is_user_set = Feature.is_user_set,
  set_user = Feature.set_user,
  unset_user = Feature.unset_user,
  is_notification_set = Feature.is_notification_set,
  set_notification = Feature.set_notification,
  unset_notification = Feature.unset_notification,
  is_year_day_access_schedules_set = Feature.is_year_day_access_schedules_set,
  set_year_day_access_schedules = Feature.set_year_day_access_schedules,
  unset_year_day_access_schedules = Feature.unset_year_day_access_schedules,
  is_holiday_schedules_set = Feature.is_holiday_schedules_set,
  set_holiday_schedules = Feature.set_holiday_schedules,
  unset_holiday_schedules = Feature.unset_holiday_schedules,
  is_unbolt_set = Feature.is_unbolt_set,
  set_unbolt = Feature.set_unbolt,
  unset_unbolt = Feature.unset_unbolt,
  is_aliro_provisioning_set = Feature.is_aliro_provisioning_set,
  set_aliro_provisioning = Feature.set_aliro_provisioning,
  unset_aliro_provisioning = Feature.unset_aliro_provisioning,
  is_alirobleuwb_set = Feature.is_alirobleuwb_set,
  set_alirobleuwb = Feature.set_alirobleuwb,
  unset_alirobleuwb = Feature.unset_alirobleuwb,
}

Feature.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(Feature, new_mt)

return Feature