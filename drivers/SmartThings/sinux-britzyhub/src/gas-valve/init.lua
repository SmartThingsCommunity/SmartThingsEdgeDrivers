-- SinuxSoft (c) 2025
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local log = require "log"

local valve_cap = capabilities.safetyValve
local onoff_cluster = clusters.OnOff

local GAS_VALVE_DEVICE_TYPE_ID = 0xFF01

local function on_off_attr_handler(driver, device, ib, response)
  if ib.data.value then
    device:emit_event_for_endpoint(ib.endpoint_id, valve_cap.valve.open())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, valve_cap.valve.closed())
  end
end

local function handle_valve_command(driver, device, cmd, cluster_command)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local req = cluster_command(device, endpoint_id)
  device:send(req)
end

local function find_default_endpoint(device, cluster)
  local eps = device:get_endpoints(cluster)
  table.sort(eps)
  for _, ep in ipairs(eps) do
    if ep ~= 0 then return ep end
  end
  log.warn(string.format("No endpoint found, using default %d", device.MATTER_DEFAULT_ENDPOINT))
  return device.MATTER_DEFAULT_ENDPOINT
end

local function component_to_endpoint(device, _)
  return find_default_endpoint(device, onoff_cluster.ID)
end

local function device_init(_, device)
  device:set_component_to_endpoint_fn(component_to_endpoint)
  device:subscribe()
end

local function info_changed(_, device)
  device:add_subscribed_attribute(onoff_cluster.attributes.OnOff)
  device:subscribe()
end

local function is_matter_gas_valve(opts, driver, device)
  for _, ep in ipairs(device.endpoints) do
    for _, dt in ipairs(ep.device_types) do
      if dt.device_type_id == GAS_VALVE_DEVICE_TYPE_ID then
        return true
      end
    end
  end
  return false
end

local gas_valve_handler = {
  NAME = "Gas Valve Handler",
  can_handle = is_matter_gas_valve,
  lifecycle_handlers = {
    init = device_init,
    infoChanged = info_changed,
  },
  matter_handlers = {
    attr = {
      [onoff_cluster.ID] = {
        [onoff_cluster.attributes.OnOff.ID] = on_off_attr_handler,
      }
    }
  },
  capability_handlers = {
    [valve_cap.ID] = {
      --[valve_cap.commands.open.NAME] = function(driver, device, cmd)
        --handle_valve_command(driver, device, cmd, onoff_cluster.server.commands.On)
      --end,
      [valve_cap.commands.close.NAME] = function(driver, device, cmd)
        handle_valve_command(driver, device, cmd, onoff_cluster.server.commands.Off)
      end,
    }
  },
  supported_capabilities = {
    valve_cap,
  },
  subscribed_attributes = {
    [valve_cap.ID] = {
      onoff_cluster.attributes.OnOff
    }
  },
}

return gas_valve_handler