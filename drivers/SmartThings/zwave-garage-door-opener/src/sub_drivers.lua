-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local lazy_load_if_possible = require "lazy_load_subdriver"
local sub_drivers = {
   lazy_load_if_possible("mimolite-garage-door"),
   lazy_load_if_possible("ecolink-zw-gdo"),
}
return sub_drivers
