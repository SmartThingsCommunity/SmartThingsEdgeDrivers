-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local lazy_load_if_possible = require "lazy_load_subdriver"
local sub_drivers = {
   lazy_load_if_possible("zwave-smoke-co-alarm-v1"),
   lazy_load_if_possible("zwave-smoke-co-alarm-v2"),
   lazy_load_if_possible("fibaro-smoke-sensor"),
   lazy_load_if_possible("apiv6_bugfix"),
}
return sub_drivers
