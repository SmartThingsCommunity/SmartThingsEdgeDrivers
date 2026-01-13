-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local fields = require "switch_utils.fields"

local SensorFields = {}

SensorFields.FLOW_BOUND_RECEIVED = "__flow_bound_received"
SensorFields.FLOW_MIN = "__flow_min"
SensorFields.FLOW_MAX = "__flow_max"

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

return SensorFields
