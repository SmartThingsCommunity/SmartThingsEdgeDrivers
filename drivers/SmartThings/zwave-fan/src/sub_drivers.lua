-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local lazy_load_if_possible = require "lazy_load_subdriver"
local sub_drivers = {
   lazy_load_if_possible("zwave-fan-3-speed"),
   lazy_load_if_possible("zwave-fan-4-speed"),
}
return sub_drivers
