-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local lazy_load_if_possible = require "lazy_load_subdriver"
local sub_drivers = {
   lazy_load_if_possible("springs-window-fashion-shade"),
   lazy_load_if_possible("iblinds-window-treatment"),
   lazy_load_if_possible("window-treatment-venetian"),
   lazy_load_if_possible("aeotec-nano-shutter"),
}
return sub_drivers
