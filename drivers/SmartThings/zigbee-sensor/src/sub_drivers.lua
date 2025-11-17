-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local lazy_load_if_possible = require "lazy_load_subdriver"
local sub_drivers = {
   lazy_load_if_possible("contact"),
   lazy_load_if_possible("motion"),
   lazy_load_if_possible("waterleak"),
   lazy_load_if_possible("motion-illuminance"),
}
return sub_drivers
