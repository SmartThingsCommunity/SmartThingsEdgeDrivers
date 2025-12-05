-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local lazy_load = require "lazy_load_subdriver"

return {
  lazy_load("zigbee-dimming-light.osram-iqbr30"),
  lazy_load("zigbee-dimming-light.zll-dimmer")
}
