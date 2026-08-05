-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local lazy_load_subdriver = require "lazy_load_subdriver"

local sub_drivers = {
    lazy_load_subdriver("zigbee-multi-button.somfy.somfy_situo_1"),
    lazy_load_subdriver("zigbee-multi-button.somfy.somfy_situo_4"),
}

return sub_drivers
