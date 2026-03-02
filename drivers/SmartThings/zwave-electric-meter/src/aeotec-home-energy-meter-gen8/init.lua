-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function device_added(driver, device)
  device:refresh()
end

local aeotec_home_energy_meter_gen8 = {
  NAME = "Aeotec Home Energy Meter Gen8",
  lifecycle_handlers = {
    added = device_added
  },
  can_handle = require("aeotec-home-energy-meter-gen8.can_handle"),
  sub_drivers = {
    require("aeotec-home-energy-meter-gen8.sub_drivers")
  }
}

return aeotec_home_energy_meter_gen8
