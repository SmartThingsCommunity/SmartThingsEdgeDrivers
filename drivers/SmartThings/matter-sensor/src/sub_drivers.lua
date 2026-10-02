-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local lazy_load_if_possible = require "lazy_load_subdriver"
local sub_drivers = {
   lazy_load_if_possible("sub_drivers.air_quality_sensor"),
   lazy_load_if_possible("sub_drivers.smoke_co_alarm"),
   lazy_load_if_possible("sub_drivers.bosch_button_contact"),
   lazy_load_if_possible("sub_drivers.aqara_fp400"),
}
return sub_drivers
