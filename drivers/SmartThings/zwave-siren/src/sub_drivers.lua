-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local lazy_load_if_possible = require "lazy_load_subdriver"
local sub_drivers = {
   lazy_load_if_possible("multifunctional-siren"),
   lazy_load_if_possible("zwave-sound-sensor"),
   lazy_load_if_possible("ecolink-wireless-siren"),
   lazy_load_if_possible("philio-sound-siren"),
   lazy_load_if_possible("aeotec-doorbell-siren"),
   lazy_load_if_possible("aeon-siren"),
   lazy_load_if_possible("yale-siren"),
   lazy_load_if_possible("zipato-siren"),
   lazy_load_if_possible("utilitech-siren"),
   lazy_load_if_possible("fortrezz"),
   lazy_load_if_possible("apiv6_bugfix"),
}
return sub_drivers
