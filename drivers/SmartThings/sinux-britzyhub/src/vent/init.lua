-- SinuxSoft (c) 2025
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local log = require "log"

local VENTILATOR_DEVICE_TYPE_ID = 0xFF03

local COMPONENT_TO_ENDPOINT_MAP = "__component_to_endpoint_map"

local function map_enum_value(map, value, default)
  return map[value] or default
end

local function find_default_endpoint(device, cluster)
  local eps = device:get_endpoints(cluster)
  table.sort(eps)
  for _, v in ipairs(eps) do
    if v ~= 0 then
      return v
    end
  end
  log.warn(string.format("No endpoint found, using default %d", device.MATTER_DEFAULT_ENDPOINT))
  return device.MATTER_DEFAULT_ENDPOINT
end

local function component_to_endpoint(device, component_name, cluster_id)
  local component_to_endpoint_map = device:get_field(COMPONENT_TO_ENDPOINT_MAP)
  if component_to_endpoint_map ~= nil and component_to_endpoint_map[component_name] ~= nil then
    return component_to_endpoint_map[component_name]
  end
  if not cluster_id then return device.MATTER_DEFAULT_ENDPOINT end
  return find_default_endpoint(device, cluster_id)
end

local endpoint_to_component = function(device, endpoint_id)
  local component_to_endpoint_map = device:get_field(COMPONENT_TO_ENDPOINT_MAP)
  if component_to_endpoint_map ~= nil then
    for comp, ep in pairs(component_to_endpoint_map) do
      if ep == endpoint_id then
        return comp
      end
    end
  end
  return "main"
end

local function on_off_attr_handler(driver, device, ib, response)
  if ib.data.value then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switch.switch.on())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switch.switch.off())
  end
end

local AC_FAN_MODE_MAP = {
  [clusters.FanControl.attributes.FanMode.LOW] = capabilities.airPurifierFanMode.airPurifierFanMode.low(),
  [clusters.FanControl.attributes.FanMode.MEDIUM] = capabilities.airPurifierFanMode.airPurifierFanMode.medium(),
  [clusters.FanControl.attributes.FanMode.HIGH] = capabilities.airPurifierFanMode.airPurifierFanMode.high(),
}

local function fan_mode_handler(driver, device, ib, response)
  local cap = capabilities.airPurifierFanMode
  if device:supports_capability_by_id(cap.ID) then
    local event = map_enum_value(AC_FAN_MODE_MAP, ib.data.value, cap.airPurifierFanMode.low())
    device:emit_event_for_endpoint(ib.endpoint_id, event)
  end
end

local function handle_switch_on(driver, device, cmd)
  local ep = component_to_endpoint(device, cmd.component, clusters.OnOff.ID)
  device:send(clusters.OnOff.server.commands.On(device, ep))
end

local function handle_switch_off(driver, device, cmd)
  local ep = component_to_endpoint(device, cmd.component, clusters.OnOff.ID)
  device:send(clusters.OnOff.server.commands.Off(device, ep))
end

local function set_air_purifier_fan_mode(driver, device, cmd)
  local args = cmd.args.airPurifierFanMode
  local mode_map = {
    low = clusters.FanControl.attributes.FanMode.LOW,
    medium = clusters.FanControl.attributes.FanMode.MEDIUM,
    high = clusters.FanControl.attributes.FanMode.HIGH,
  }
  local ep = component_to_endpoint(device, cmd.component, clusters.FanControl.ID)
  local mode = mode_map[args] or clusters.FanControl.attributes.FanMode.OFF
  device:send(clusters.FanControl.attributes.FanMode:write(device, ep, mode))
end

local function device_init(driver, device)
  device:set_component_to_endpoint_fn(component_to_endpoint)
  device:set_endpoint_to_component_fn(endpoint_to_component)
  device:subscribe()
end

local function info_changed(driver, device, event, args)
  for _, attr in ipairs({
    clusters.OnOff.attributes.OnOff,
    clusters.FanControl.attributes.FanMode,
  }) do
    device:add_subscribed_attribute(attr)
  end
  device:subscribe()
end

local function is_matter_ventilator(opts, driver, device)
  for _, ep in ipairs(device.endpoints) do
    for _, dt in ipairs(ep.device_types) do
      if dt.device_type_id == VENTILATOR_DEVICE_TYPE_ID then
        return true
      end
    end
  end
  return false
end

local ventilator_handler = {
  NAME = "Ventilator Handler",
  can_handle = is_matter_ventilator,
  lifecycle_handlers = {
    init = device_init,
    infoChanged = info_changed,
  },
  matter_handlers = {
    attr = {
      [clusters.OnOff.ID] = {
        [clusters.OnOff.attributes.OnOff.ID] = on_off_attr_handler,
      },
      [clusters.FanControl.ID] = {
        [clusters.FanControl.attributes.FanMode.ID] = fan_mode_handler,
      },
    }
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = handle_switch_on,
      [capabilities.switch.commands.off.NAME] = handle_switch_off,
    },
    [capabilities.airPurifierFanMode.ID] = {
      [capabilities.airPurifierFanMode.commands.setAirPurifierFanMode.NAME] = set_air_purifier_fan_mode,
    },
  },
  supported_capabilities = {
    capabilities.switch,
    capabilities.airPurifierFanMode,
  },
}

return ventilator_handler