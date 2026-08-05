-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local lazy_load_if_possible = require "lazy_load_subdriver"
local sub_drivers = {
    lazy_load_if_possible("frient.EMIZB-151")
}

return sub_drivers
