-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local lazy_load_if_possible = require "lazy_load_subdriver"
local sub_drivers = {
   lazy_load_if_possible("zwave-multi-button/aeotec-keyfob"),
   lazy_load_if_possible("zwave-multi-button/fibaro-keyfob"),
   lazy_load_if_possible("zwave-multi-button/aeotec-minimote"),
   lazy_load_if_possible("zwave-multi-button/shelly_wave_i4"),
}
return sub_drivers
