-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local defaults = require "st.zigbee.defaults"
local capabilities = require "st.capabilities"


local generic_contact_sensor = {
  NAME = "Generic Contact Sensor",
  supported_capabilities = {
    capabilities.contactSensor
  },
  can_handle = require("contact.can_handle"),
}
defaults.register_for_default_handlers(generic_contact_sensor, generic_contact_sensor.supported_capabilities)
return generic_contact_sensor