-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local lazy_load_if_possible = require "lazy_load_subdriver"
local sub_drivers = {
   lazy_load_if_possible("matter-cook-top"),
   lazy_load_if_possible("matter-dishwasher"),
   lazy_load_if_possible("matter-extractor-hood"),
   lazy_load_if_possible("matter-laundry"),
   lazy_load_if_possible("matter-microwave-oven"),
   lazy_load_if_possible("matter-oven"),
   lazy_load_if_possible("matter-refrigerator"),
}
return sub_drivers
