-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local lazy_load_if_possible = require "lazy_load_subdriver"
local sub_drivers = {
   lazy_load_if_possible("fibaro-door-window-sensor/fibaro-door-window-sensor-1"),
   lazy_load_if_possible("fibaro-door-window-sensor/fibaro-door-window-sensor-2"),
}
return sub_drivers
