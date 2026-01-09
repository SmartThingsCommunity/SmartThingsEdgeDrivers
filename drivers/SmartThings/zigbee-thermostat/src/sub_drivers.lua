-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local lazy_load_if_possible = require "lazy_load_subdriver"
local sub_drivers = {
   lazy_load_if_possible("zenwithin"),
   lazy_load_if_possible("fidure"),
   lazy_load_if_possible("sinope"),
   lazy_load_if_possible("stelpro-ki-zigbee-thermostat"),
   lazy_load_if_possible("stelpro"),
   lazy_load_if_possible("lux-konoz"),
   lazy_load_if_possible("leviton"),
   lazy_load_if_possible("danfoss"),
   lazy_load_if_possible("popp"),
   lazy_load_if_possible("vimar"),
   lazy_load_if_possible("resideo_korea"),
   lazy_load_if_possible("aqara"),
}
return sub_drivers
