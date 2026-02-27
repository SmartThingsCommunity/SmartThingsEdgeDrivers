-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local configurations = require "configurations"



local function component_to_endpoint(device, component_id)
  if component_id == "main" then
    return device.fingerprinted_endpoint_id
  else
    local ep_num = component_id:match("switch(%d)")
    return ep_num and tonumber(ep_num) or device.fingerprinted_endpoint_id
  end
end

local function endpoint_to_component(device, ep)
  if ep == device.fingerprinted_endpoint_id then
    return "main"
  else
    return string.format("switch%d", ep)
  end
end

local device_init = function(self, device)
  device:set_component_to_endpoint_fn(component_to_endpoint)
  device:set_endpoint_to_component_fn(endpoint_to_component)
end

local function on_handler(driver, device, command)
  local attr = capabilities.switch.switch
  if command.component == "main" then
    -- The main component is set to on by the device and cannot be set to on itself. It can only trigger off
    device:emit_event_for_endpoint(device.fingerprinted_endpoint_id, attr.on())
    device.thread:call_with_delay(1, function(d)
    device:emit_event_for_endpoint(device.fingerprinted_endpoint_id, attr.off())
    end)
  else
    device:send_to_component(command.component, zcl_clusters.OnOff.server.commands.On(device))
  end
end

local laisiao_bath_heater = {
  NAME = "Zigbee Laisiao Bathroom Heater",
  supported_capabilities = {
    capabilities.switch,
  },
  lifecycle_handlers = {
    init = configurations.reconfig_wrapper(device_init),
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = on_handler
    }
  },
  can_handle = require("laisiao.can_handle"),
}

return laisiao_bath_heater
