-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local lazy_load_if_possible = require "lazy_load_subdriver"
local sub_drivers = {
    lazy_load_if_possible("using-old-capabilities.samsungsds"),
    lazy_load_if_possible("using-old-capabilities.yale"),
    lazy_load_if_possible("using-old-capabilities.yale-fingerprint-lock"),
    lazy_load_if_possible("using-old-capabilities.lock-without-codes")
}
return sub_drivers