-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local lazy_load_if_possible = require "lazy_load_subdriver"
local sub_drivers = {
   lazy_load_if_possible("aqara"),
   lazy_load_if_possible("zigbee-water-freeze"),
   lazy_load_if_possible("leaksmart"),
   lazy_load_if_possible("frient"),
   lazy_load_if_possible("thirdreality"),
   lazy_load_if_possible("sengled"),
   lazy_load_if_possible("sinope"),
}
return sub_drivers
