-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local lazy_load_if_possible = require "lazy_load_subdriver"
local sub_drivers = {
   lazy_load_if_possible("aqara.roller-shade"),
   lazy_load_if_possible("aqara.curtain-driver-e1"),
   lazy_load_if_possible("aqara.version"),
}
return sub_drivers
