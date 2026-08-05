-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local lazy_load_if_possible = require "lazy_load_subdriver"
local sub_drivers = {
   lazy_load_if_possible("zwave-smoke-co-alarm-v2.fibaro-co-sensor-zw5"),
}
return sub_drivers
