-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function component_to_endpoint(device, component_id)
  if component_id == "main" then
    return {1}
  else
    return {2}
  end
end

local function endpoint_to_component(device, ep)
  local switch_comp = string.format("smartplug%d", ep - 1)
  if device.profile.components[switch_comp] ~= nil then
    return switch_comp
  else
    return "main"
  end
end

local function device_init(self, device)
  device:set_component_to_endpoint_fn(component_to_endpoint)
  device:set_endpoint_to_component_fn(endpoint_to_component)
end

local fibaro_wall_plug = {
  NAME = "fibaro wall plug us",
  lifecycle_handlers = {
    init = device_init
  },
  can_handle = require("fibaro-wall-plug-us.can_handle"),
}

return fibaro_wall_plug
