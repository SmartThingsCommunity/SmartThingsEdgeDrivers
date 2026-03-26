-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local lazy_load_if_possible = require "lazy_load_subdriver"
local sub_drivers = {
   lazy_load_if_possible("aeotec-radiator-thermostat"),
   lazy_load_if_possible("popp-radiator-thermostat"),
   lazy_load_if_possible("ct100-thermostat"),
   lazy_load_if_possible("fibaro-heat-controller"),
   lazy_load_if_possible("stelpro-ki-thermostat"),
   lazy_load_if_possible("qubino-flush-thermostat"),
   lazy_load_if_possible("thermostat-heating-battery"),
   lazy_load_if_possible("apiv6_bugfix"),
}
return sub_drivers
