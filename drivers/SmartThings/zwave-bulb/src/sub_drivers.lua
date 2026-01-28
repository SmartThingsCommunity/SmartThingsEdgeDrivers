-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local lazy_load_if_possible = require "lazy_load_subdriver"
local sub_drivers = {
   lazy_load_if_possible("aeotec-led-bulb-6"),
   lazy_load_if_possible("aeon-multiwhite-bulb"),
   lazy_load_if_possible("fibaro-rgbw-controller"),
}
return sub_drivers
