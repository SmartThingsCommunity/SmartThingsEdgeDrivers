-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"

local SensorFields = {}

SensorFields.DEVICE_TYPE_ID = {
  RAIN_SENSOR = 0x0044,
  WATER_FREEZE_DETECTOR = 0x0041,
  WATER_LEAK_DETECTOR = 0x0043,
  CONTACT_SENSOR = 0x0015,
  SMOKE_CO_ALARM = 0x0076,
  AIR_QUALITY_SENSOR = 0x002C,
  ROOT_NODE = 0x0016,
  POWER_SOURCE = 0x0011,
}

SensorFields.TEMP_BOUND_RECEIVED = "__temp_bound_received"
SensorFields.TEMP_MIN = "__temp_min"
SensorFields.TEMP_MAX = "__temp_max"
SensorFields.FLOW_BOUND_RECEIVED = "__flow_bound_received"
SensorFields.FLOW_MIN = "__flow_min"
SensorFields.FLOW_MAX = "__flow_max"

SensorFields.battery_support = {
  NO_BATTERY = "NO_BATTERY",
  BATTERY_LEVEL = "BATTERY_LEVEL",
  BATTERY_PERCENTAGE = "BATTERY_PERCENTAGE"
}

SensorFields.BOOLEAN_DEVICE_TYPE_INFO = {
  ["RAIN_SENSOR"] = { id = SensorFields.DEVICE_TYPE_ID.RAIN_SENSOR, sensitivity_preference = "rainSensitivity", sensitivity_max = "rainMax" },
  ["WATER_FREEZE_DETECTOR"] = { id = SensorFields.DEVICE_TYPE_ID.WATER_FREEZE_DETECTOR, sensitivity_preference = "freezeSensitivity", sensitivity_max = "freezeMax" },
  ["WATER_LEAK_DETECTOR"] = { id = SensorFields.DEVICE_TYPE_ID.WATER_LEAK_DETECTOR, sensitivity_preference = "leakSensitivity", sensitivity_max = "leakMax" },
  ["CONTACT_SENSOR"] = { id = SensorFields.DEVICE_TYPE_ID.CONTACT_SENSOR, sensitivity_preference = "N/A", sensitivity_max = "N/A" },
}

SensorFields.ORDERED_DEVICE_TYPE_INFO = {
  "RAIN_SENSOR",
  "WATER_FREEZE_DETECTOR",
  "WATER_LEAK_DETECTOR",
  "CONTACT_SENSOR"
}

SensorFields.BOOLEAN_CAP_EVENT_MAP = {
  [true] = {
      ["WATER_FREEZE_DETECTOR"] = capabilities.temperatureAlarm.temperatureAlarm.freeze(),
      ["WATER_LEAK_DETECTOR"] = capabilities.waterSensor.water.wet(),
      ["RAIN_SENSOR"] = capabilities.rainSensor.rain.detected(),
      ["CONTACT_SENSOR"] =  capabilities.contactSensor.contact.closed(),
  },
  [false] = {
      ["WATER_FREEZE_DETECTOR"] = capabilities.temperatureAlarm.temperatureAlarm.cleared(),
      ["WATER_LEAK_DETECTOR"] = capabilities.waterSensor.water.dry(),
      ["RAIN_SENSOR"] = capabilities.rainSensor.rain.undetected(),
      ["CONTACT_SENSOR"] =  capabilities.contactSensor.contact.open(),
  }
}

return SensorFields
