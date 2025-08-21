-- SinuxSoft (c) 2025
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local log = require "log"

local elevator_cap = capabilities.elevatorCall
local onoff_cluster = clusters.OnOff

local ELEVATOR_DEVICE_TYPE_ID = 0xFF02

local function on_off_attr_handler(driver, device, ib, response)
  if ib.data.value then
    device:emit_event_for_endpoint(ib.endpoint_id, elevator_cap.callStatus.called())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, elevator_cap.callStatus.standby())
  end
end

local function handle_elevator_call(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local req = onoff_cluster.server.commands.On(device, endpoint_id)
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

local function component_to_endpoint(device, component_name, cluster_id)
  return find_default_endpoint(device, clusters.OnOff.ID)
end

local function device_init(driver, device)
  device:set_component_to_endpoint_fn(component_to_endpoint)
  device:subscribe()
end

local function info_changed(driver, device, event, args)
  device:add_subscribed_attribute(onoff_cluster.attributes.OnOff)
  device:subscribe()
end

local function is_matter_elevator(opts, driver, device)
  for _, ep in ipairs(device.endpoints) do
    for _, dt in ipairs(ep.device_types) do
      if dt.device_type_id == ELEVATOR_DEVICE_TYPE_ID then
        return true
      end
    end
  end
  return false
end

local elevator_handler = {
  NAME = "Elevator Handler",
  can_handle = is_matter_elevator,
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
    [elevator_cap.ID] = {
      [elevator_cap.commands.call.NAME] = handle_elevator_call,
    }
  },
  supported_capabilities = {
    elevator_cap,
  },
  subscribed_attributes = {
    [elevator_cap.ID] = {
      onoff_cluster.attributes.OnOff
    }
  },
}

return elevator_handler