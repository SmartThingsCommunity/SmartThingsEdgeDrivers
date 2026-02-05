-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local lazy_load_if_possible = require "lazy_load_subdriver"
local sub_drivers = {
   lazy_load_if_possible("using-old-capabilities.zwave-alarm-v1-lock"),
   lazy_load_if_possible("using-old-capabilities.schlage-lock"),
   lazy_load_if_possible("using-old-capabilities.samsung-lock"),
   lazy_load_if_possible("using-old-capabilities.keywe-lock"),
}
return sub_drivers
