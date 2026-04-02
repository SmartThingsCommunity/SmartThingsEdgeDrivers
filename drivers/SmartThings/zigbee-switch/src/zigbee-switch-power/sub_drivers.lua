-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local lazy_load = require "lazy_load_subdriver"

return {
  lazy_load("zigbee-switch-power.aurora-relay"),
  lazy_load("zigbee-switch-power.vimar")
}
