-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local lazy_load_if_possible = require "lazy_load_subdriver"
local sub_drivers = {
    lazy_load_if_possible("aeotec-home-energy-meter-gen8.1-phase"),
    lazy_load_if_possible("aeotec-home-energy-meter-gen8.2-phase"),
    lazy_load_if_possible("aeotec-home-energy-meter-gen8.3-phase")
}
return sub_drivers
