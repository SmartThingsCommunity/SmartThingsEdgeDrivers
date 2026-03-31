-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local lazy_load_if_possible = require "lazy_load_subdriver"
local sub_drivers = {
   lazy_load_if_possible("zwave-alarm-v1-lock"),
   lazy_load_if_possible("schlage-lock"),
   lazy_load_if_possible("samsung-lock"),
   lazy_load_if_possible("keywe-lock"),
   lazy_load_if_possible("apiv6_bugfix"),
}
return sub_drivers
