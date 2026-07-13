-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local lazy_load_if_possible = require "lazy_load_subdriver"
local sub_drivers = {
   lazy_load_if_possible("vimar"),
   lazy_load_if_possible("aqara"),
   lazy_load_if_possible("feibit"),
   lazy_load_if_possible("somfy"),
   lazy_load_if_possible("invert-lift-percentage"),
   lazy_load_if_possible("rooms-beautiful"),
   lazy_load_if_possible("axis"),
   lazy_load_if_possible("yoolax"),
   lazy_load_if_possible("hanssem"),
   lazy_load_if_possible("screen-innovations"),
   lazy_load_if_possible("VIVIDSTORM"),
   lazy_load_if_possible("HOPOsmart"),
}
return sub_drivers
