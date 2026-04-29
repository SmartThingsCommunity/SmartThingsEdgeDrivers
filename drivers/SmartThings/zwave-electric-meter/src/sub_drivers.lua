-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local lazy_load_if_possible = require "lazy_load_subdriver"
local sub_drivers = {
   lazy_load_if_possible("qubino-meter"),
   lazy_load_if_possible("aeotec-gen5-meter"),
   lazy_load_if_possible("aeon-meter"),
   lazy_load_if_possible("aeotec-home-energy-meter-gen8"),
}
return sub_drivers
