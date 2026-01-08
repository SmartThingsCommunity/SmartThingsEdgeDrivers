-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local fields = require "switch_utils.fields"

local SensorFields = {}

SensorFields.FLOW_BOUND_RECEIVED = "__flow_bound_received"
SensorFields.FLOW_MIN = "__flow_min"
SensorFields.FLOW_MAX = "__flow_max"

-- Mapping between true/false meaning from BooleanState capability and capability-specific attributes, defined per device type
SensorFields.BOOLEAN_STATE_CAPABILITY_MAP = {
  [true] = {
    [fields.DEVICE_TYPE_ID.WATER_FREEZE_DETECTOR] = capabilities.temperatureAlarm.temperatureAlarm.freeze(),
    [fields.DEVICE_TYPE_ID.WATER_LEAK_DETECTOR] = capabilities.waterSensor.water.wet(),
    [fields.DEVICE_TYPE_ID.RAIN_SENSOR] = capabilities.rainSensor.rain.detected(),
    [fields.DEVICE_TYPE_ID.CONTACT_SENSOR] =  capabilities.contactSensor.contact.closed(),
  },
  [false] = {
    [fields.DEVICE_TYPE_ID.WATER_FREEZE_DETECTOR] = capabilities.temperatureAlarm.temperatureAlarm.cleared(),
    [fields.DEVICE_TYPE_ID.WATER_LEAK_DETECTOR] = capabilities.waterSensor.water.dry(),
    [fields.DEVICE_TYPE_ID.RAIN_SENSOR] = capabilities.rainSensor.rain.undetected(),
    [fields.DEVICE_TYPE_ID.CONTACT_SENSOR] =  capabilities.contactSensor.contact.open(),
  }
}

-- Generic profile names for different sensor device types 
SensorFields.DEVICE_TYPE_PROFILE_MAP = {
  [fields.DEVICE_TYPE_ID.CONTACT_SENSOR] = "contact",
  [fields.DEVICE_TYPE_ID.FLOW_SENSOR] = "flow",
  [fields.DEVICE_TYPE_ID.HUMIDITY_SENSOR] = "humidity",
  [fields.DEVICE_TYPE_ID.LIGHT_SENSOR] = "illuminance",
  [fields.DEVICE_TYPE_ID.OCCUPANCY_SENSOR] = "occupancy",
  [fields.DEVICE_TYPE_ID.PRESSURE_SENSOR] = "pressure",
  [fields.DEVICE_TYPE_ID.RAIN_SENSOR] = "rain",
  [fields.DEVICE_TYPE_ID.TEMPERATURE_SENSOR] = "temperature",
  [fields.DEVICE_TYPE_ID.WATER_FREEZE_DETECTOR] = "freeze",
  [fields.DEVICE_TYPE_ID.WATER_LEAK_DETECTOR] = "leak",
}

-- Device types supported by the motion/presence profiles
SensorFields.OCCUPANCY_PROFILE_SUPPORTED_DEVICE_TYPES = {
  fields.DEVICE_TYPE_ID.CONTACT_SENSOR,
  fields.DEVICE_TYPE_ID.HUMIDITY_SENSOR,
  fields.DEVICE_TYPE_ID.LIGHT_SENSOR,
  fields.DEVICE_TYPE_ID.OCCUPANCY_SENSOR,
  fields.DEVICE_TYPE_ID.TEMPERATURE_SENSOR,
}

-- Device types supported by the temperature-humidity profile
SensorFields.TEMP_HUMIDITY_PROFILE_SUPPORTED_DEVICE_TYPES = {
  fields.DEVICE_TYPE_ID.HUMIDITY_SENSOR,
  fields.DEVICE_TYPE_ID.PRESSURE_SENSOR,
  fields.DEVICE_TYPE_ID.TEMPERATURE_SENSOR,
}

return SensorFields
