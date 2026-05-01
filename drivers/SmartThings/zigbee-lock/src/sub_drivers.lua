-- Copyright 2026 SmartThings
-- Licensed under the Apache License, Version 2.0

local lazy_load_if_possible = require "lazy_load_subdriver"
local sub_drivers = {
   lazy_load_if_possible("legacy-handlers"),
   lazy_load_if_possible("samsungsds"),
   lazy_load_if_possible("yale"),
   lazy_load_if_possible("yale-fingerprint-lock"),
}
return sub_drivers
