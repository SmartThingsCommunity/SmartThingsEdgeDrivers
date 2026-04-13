-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local lazy_load_if_possible = require "lazy_load_subdriver"
local sub_drivers = {
   lazy_load_if_possible("aqara"),
   lazy_load_if_possible("aurora-contact-sensor"),
   lazy_load_if_possible("contact-temperature-sensor"),
   lazy_load_if_possible("multi-sensor"),
   lazy_load_if_possible("smartsense-multi"),
   lazy_load_if_possible("sengled"),
   lazy_load_if_possible("frient"),
}
return sub_drivers
