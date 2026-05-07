-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=1 })

local function device_added(driver, device)
  device:refresh()
end

local function component_to_endpoint(device, component_id)
  local ep_num = component_id:match("clamp(%d)")
  return { ep_num and tonumber(ep_num) }
end

local function endpoint_to_component(device, ep)
  local meter_comp = string.format("clamp%d", ep)
  if device.profile.components[meter_comp] ~= nil then
    return meter_comp
  else
    return "main"
  end
end

local device_init = function(self, device)
  device:set_component_to_endpoint_fn(component_to_endpoint)
  device:set_endpoint_to_component_fn(endpoint_to_component)
end

local do_configure = function (self, device)
  device:send(Configuration:Set({parameter_number = 111, configuration_value = 300, size = 4})) -- ...every 5 min
  device:send(Configuration:Set({parameter_number = 112, configuration_value = 300, size = 4})) -- ...every 5 min
  device:send(Configuration:Set({parameter_number = 113, configuration_value = 300, size = 4})) -- ...every 5 min
end

local aeotec_home_energy_meter_gen8 = {
  NAME = "Aeotec Home Energy Meter Gen8",
  lifecycle_handlers = {
    added = device_added,
    init = device_init,
    doConfigure = do_configure
  },
  can_handle = require("aeotec-home-energy-meter-gen8.can_handle"),
  sub_drivers = {
    require("aeotec-home-energy-meter-gen8.sub_drivers")
  }
}

return aeotec_home_energy_meter_gen8
