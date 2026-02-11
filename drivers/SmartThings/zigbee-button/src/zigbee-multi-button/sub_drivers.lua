-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local lazy_load_if_possible = require "lazy_load_subdriver"
local sub_drivers = {
   lazy_load_if_possible("zigbee-multi-button.ikea"),
   lazy_load_if_possible("zigbee-multi-button.somfy"),
   lazy_load_if_possible("zigbee-multi-button.ecosmart"),
   lazy_load_if_possible("zigbee-multi-button.centralite"),
   lazy_load_if_possible("zigbee-multi-button.adurosmart"),
   lazy_load_if_possible("zigbee-multi-button.heiman"),
   lazy_load_if_possible("zigbee-multi-button.shinasystems"),
   lazy_load_if_possible("zigbee-multi-button.robb"),
   lazy_load_if_possible("zigbee-multi-button.wallhero"),
   lazy_load_if_possible("zigbee-multi-button.SLED"),
   lazy_load_if_possible("zigbee-multi-button.vimar"),
   lazy_load_if_possible("zigbee-multi-button.linxura"),
   lazy_load_if_possible("zigbee-multi-button.zunzunbee"),
}
return sub_drivers
