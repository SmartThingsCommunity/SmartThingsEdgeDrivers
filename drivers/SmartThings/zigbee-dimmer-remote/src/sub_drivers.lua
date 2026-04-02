-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local lazy_load_if_possible = require "lazy_load_subdriver"

local sub_drivers = {
    lazy_load_if_possible("zigbee-accessory-dimmer"),
    lazy_load_if_possible("zigbee-battery-accessory-dimmer"),
}

return sub_drivers
