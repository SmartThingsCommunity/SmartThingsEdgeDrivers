-- SinuxSoft (c) 2025
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local utils = require "st.utils"
local log = require "log"

local COMPONENT_TO_ENDPOINT_MAP = "__component_to_endpoint_map"

local WIND_MODE_MAP = {
  [0] = capabilities.windMode.windMode.sleepWind,
  [1] = capabilities.windMode.windMode.naturalWind,
}

local ROCK_MODE_MAP = {
  [0] = capabilities.fanOscillationMode.fanOscillationMode.horizontal,
  [1] = capabilities.fanOscillationMode.fanOscillationMode.vertical,
  [2] = capabilities.fanOscillationMode.fanOscillationMode.swing,
}

local function map_enum_value(map, value, default)
  return map[value] or default
end

local function generate_bitmask_event_handler(map, capability, default_event)
  return function(_, device, ib, _)
    for index, event_func in pairs(map) do
      if ((ib.data.value >> index) & 1) > 0 then
        device:emit_event_for_endpoint(ib.endpoint_id, event_func())
        return
      end
    end
    device:emit_event_for_endpoint(ib.endpoint_id, default_event())
  end
end

local function component_to_endpoint(device, component_name, cluster_id)
  local map = device:get_field(COMPONENT_TO_ENDPOINT_MAP)
  return (map and map[component_name]) or device.MATTER_DEFAULT_ENDPOINT
end

local function on_off_attr_handler(_, device, ib, _)
  if ib.data.value then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switch.switch.on())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switch.switch.off())
  end
end

local AC_FAN_MODE_MAP = {
  [clusters.FanControl.attributes.FanMode.OFF] = capabilities.airPurifierFanMode.airPurifierFanMode.off(),
  [clusters.FanControl.attributes.FanMode.LOW] = capabilities.airPurifierFanMode.airPurifierFanMode.low(),
  [clusters.FanControl.attributes.FanMode.MEDIUM] = capabilities.airPurifierFanMode.airPurifierFanMode.medium(),
  [clusters.FanControl.attributes.FanMode.HIGH] = capabilities.airPurifierFanMode.airPurifierFanMode.high(),
  [clusters.FanControl.attributes.FanMode.AUTO] = capabilities.airPurifierFanMode.airPurifierFanMode.auto(),
}

local function fan_mode_handler(_, device, ib, _)
  local cap = capabilities.airPurifierFanMode
  if device:supports_capability_by_id(cap.ID) then
    local event = map_enum_value(AC_FAN_MODE_MAP, ib.data.value, cap.airPurifierFanMode.auto())
    device:emit_event_for_endpoint(ib.endpoint_id, event)
  end
end

local function fan_speed_percent_attr_handler(_, device, ib, _)
  local value = utils.clamp_value(ib.data.value or 0, 0, 100)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.fanSpeedPercent.percent(value))
end

local wind_setting_handler = generate_bitmask_event_handler(WIND_MODE_MAP, capabilities.windMode,
  capabilities.windMode.windMode.noWind)
local rock_setting_handler = generate_bitmask_event_handler(ROCK_MODE_MAP, capabilities.fanOscillationMode,
  capabilities.fanOscillationMode.fanOscillationMode.off)

local function handle_switch_on(_, device, cmd)
  local ep = component_to_endpoint(device, cmd.component, clusters.OnOff.ID)
  device:send(clusters.OnOff.server.commands.On(device, ep))
end

local function handle_switch_off(_, device, cmd)
  local ep = component_to_endpoint(device, cmd.component, clusters.OnOff.ID)
  device:send(clusters.OnOff.server.commands.Off(device, ep))
end

local function set_air_purifier_fan_mode(_, device, cmd)
  local args = cmd.args.airPurifierFanMode
  local mode_map = {
    low = clusters.FanControl.attributes.FanMode.LOW,
    sleep = clusters.FanControl.attributes.FanMode.LOW,
    quiet = clusters.FanControl.attributes.FanMode.LOW,
    windFree = clusters.FanControl.attributes.FanMode.LOW,
    medium = clusters.FanControl.attributes.FanMode.MEDIUM,
    high = clusters.FanControl.attributes.FanMode.HIGH,
    auto = clusters.FanControl.attributes.FanMode.AUTO,
    off = clusters.FanControl.attributes.FanMode.OFF,
  }
  local ep = component_to_endpoint(device, cmd.component, clusters.FanControl.ID)
  local mode = mode_map[args] or clusters.FanControl.attributes.FanMode.OFF
  device:send(clusters.FanControl.attributes.FanMode:write(device, ep, mode))
end

local function device_init(_, device)
  device:set_component_to_endpoint_fn(component_to_endpoint)
  device:subscribe()
end

local function info_changed(_, device)
  for _, attr in ipairs({
    clusters.OnOff.attributes.OnOff,
    clusters.FanControl.attributes.FanMode,
    clusters.FanControl.attributes.PercentCurrent,
    clusters.FanControl.attributes.WindSetting,
    clusters.FanControl.attributes.RockSetting,
  }) do
    device:add_subscribed_attribute(attr)
  end
  device:subscribe()
end

local ventilator_handler = {
  NAME = "Ventilator Handler",
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
        [clusters.FanControl.attributes.PercentCurrent.ID] = fan_speed_percent_attr_handler,
        [clusters.FanControl.attributes.WindSetting.ID] = wind_setting_handler,
        [clusters.FanControl.attributes.RockSetting.ID] = rock_setting_handler,
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
--     capabilities.fanSpeedPercent,
--     capabilities.windMode,
--     capabilities.fanOscillationMode,
  },
}

return ventilator_handler