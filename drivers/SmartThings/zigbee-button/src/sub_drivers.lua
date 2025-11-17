-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local lazy_load_if_possible = require "lazy_load_subdriver"
local sub_drivers = {
   lazy_load_if_possible("aqara"),
   lazy_load_if_possible("pushButton"),
   lazy_load_if_possible("frient"),
   lazy_load_if_possible("zigbee-multi-button"),
   lazy_load_if_possible("dimming-remote"),
   lazy_load_if_possible("iris"),
   lazy_load_if_possible("samjin"),
   lazy_load_if_possible("ewelink"),
   lazy_load_if_possible("thirdreality"),
   lazy_load_if_possible("ezviz"),
}
return sub_drivers
