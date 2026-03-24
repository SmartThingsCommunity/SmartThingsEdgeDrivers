-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"



local device_added = function(self, device)
  device:emit_event(capabilities.battery.battery(100))
end

local climax_technology_carbon_monoxide = {
  NAME = "ClimaxTechnology Carbon Monoxide",
  lifecycle_handlers = {
    added = device_added
  },
  can_handle = require("ClimaxTechnology.can_handle"),
}

return climax_technology_carbon_monoxide
