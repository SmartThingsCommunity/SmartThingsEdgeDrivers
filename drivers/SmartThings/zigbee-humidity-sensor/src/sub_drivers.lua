-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local lazy_load_if_possible = require "lazy_load_subdriver"
local sub_drivers = {
   lazy_load_if_possible("aqara"),
   lazy_load_if_possible("plant-link"),
   lazy_load_if_possible("plaid-systems"),
   lazy_load_if_possible("centralite-sensor"),
   lazy_load_if_possible("heiman-sensor"),
   lazy_load_if_possible("frient-sensor"),
}
return sub_drivers
