-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local sonoff_thermostat = {
  NAME = "SONOFF Thermostat Handler",
  sub_drivers = require("sonoff.sub_drivers"),
  can_handle = require("sonoff.can_handle"),
}

return sonoff_thermostat
