-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local lazy_load_if_possible = require "lazy_load_subdriver"
local sub_drivers = {
   lazy_load_if_possible("sub_drivers.air_quality_sensor"),
   lazy_load_if_possible("sub_drivers.smoke_co_alarm"),
   lazy_load_if_possible("sub_drivers.bosch_button_contact"),
}
return sub_drivers
