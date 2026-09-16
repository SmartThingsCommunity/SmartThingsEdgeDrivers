-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local lazy_load_if_possible = require "lazy_load_subdriver"
local sub_drivers = {
   lazy_load_if_possible("legacy-handlers.zwave-alarm-v1-lock"),
   lazy_load_if_possible("legacy-handlers.schlage-lock"),
   lazy_load_if_possible("legacy-handlers.samsung-lock"),
   lazy_load_if_possible("legacy-handlers.keywe-lock"),
}
return sub_drivers
