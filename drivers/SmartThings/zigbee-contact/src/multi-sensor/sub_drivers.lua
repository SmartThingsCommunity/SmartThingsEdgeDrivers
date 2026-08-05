-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local lazy_load_if_possible = require "lazy_load_subdriver"
local sub_drivers = {
   lazy_load_if_possible("multi-sensor/smartthings-multi"),
   lazy_load_if_possible("multi-sensor/samjin-multi"),
   lazy_load_if_possible("multi-sensor/centralite-multi"),
   lazy_load_if_possible("multi-sensor/thirdreality-multi"),
}
return sub_drivers
