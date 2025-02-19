-- Copyright 2024 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local utils = require "st.utils"

local EXTRACTOR_HOOD_DEVICE_TYPE_ID = 0x007A
local ON_OFF_LIGHT_DEVICE_TYPE_ID = 0x0100
local ON_OFF_LIGHT_SWITCH_DEVICE_TYPE_ID = 0x0103

local version = require "version"
if version.api < 10 then
  clusters.ActivatedCarbonFilterMonitoring = require "ActivatedCarbonFilterMonitoring"
  clusters.HepaFilterMonitoring = require "HepaFilterMonitoring"
end

local COMPONENT_TO_ENDPOINT_MAP = "__component_to_endpoint_map"

local WIND_MODE_MAP = {
  [0]		= capabilities.windMode.windMode.sleepWind,
  [1]		= capabilities.windMode.windMode.naturalWind
}

-- Helper functions --
local function get_endpoints_for_dt(device, device_type)
  local endpoints = {}
  for _, ep in ipairs(device.endpoints) do
    for _, dt in ipairs(ep.device_types) do
      if dt.device_type_id == device_type then
        table.insert(endpoints, ep.endpoint_id)
        break
      end
    end
  end
  table.sort(endpoints)
  return endpoints
end

local function endpoint_to_component(device, ep)
  local map = device:get_field(COMPONENT_TO_ENDPOINT_MAP) or {}
  for component, endpoint in pairs(map) do
    if endpoint == ep then
      return component
    end
  end
  return "main"
end

local function component_to_endpoint(device, component)
  local map = device:get_field(COMPONENT_TO_ENDPOINT_MAP) or {}
  if map[component] then
    return map[component]
  end
  return device.MATTER_DEFAULT_ENDPOINT
end

local function device_init(driver, device)
  device:subscribe()
  device:set_endpoint_to_component_fn(endpoint_to_component)
  device:set_component_to_endpoint_fn(component_to_endpoint)
end

local function device_added(driver, device)
  local extractor_hood_endpoint = get_endpoints_for_dt(device, EXTRACTOR_HOOD_DEVICE_TYPE_ID)[1]
  local componentToEndpointMap = {
    ["main"] = extractor_hood_endpoint
  }
  local on_off_light_device_type_endpoint = get_endpoints_for_dt(device, ON_OFF_LIGHT_DEVICE_TYPE_ID)[1]
  local on_off_light_switch_device_type_endpoint = get_endpoints_for_dt(device, ON_OFF_LIGHT_SWITCH_DEVICE_TYPE_ID)[1]
  if on_off_light_device_type_endpoint and
    device:supports_server_cluster(clusters.OnOff.ID, on_off_light_device_type_endpoint) then
    componentToEndpointMap["light"] = on_off_light_device_type_endpoint
  elseif on_off_light_switch_device_type_endpoint and
    device:supports_server_cluster(clusters.OnOff.ID, on_off_light_switch_device_type_endpoint) then
    componentToEndpointMap["light"] = on_off_light_switch_device_type_endpoint
  end
  device:set_field(COMPONENT_TO_ENDPOINT_MAP, componentToEndpointMap, { persist = true })
end

-- Matter Handlers --
local function is_matter_extractor_hood(opts, driver, device)
  for _, ep in ipairs(device.endpoints) do
    for _, dt in ipairs(ep.device_types) do
      if dt.device_type_id == EXTRACTOR_HOOD_DEVICE_TYPE_ID then
        return true
      end
    end
  end
  return false
end

local function fan_mode_handler(driver, device, ib, response)
  if ib.data.value == clusters.FanControl.attributes.FanMode.OFF then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.fanMode.fanMode.off())
  elseif ib.data.value == clusters.FanControl.attributes.FanMode.LOW then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.fanMode.fanMode.low())
  elseif ib.data.value == clusters.FanControl.attributes.FanMode.MEDIUM then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.fanMode.fanMode.medium())
  elseif ib.data.value == clusters.FanControl.attributes.FanMode.HIGH then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.fanMode.fanMode.high())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.fanMode.fanMode.auto())
  end
end

local function fan_mode_sequence_handler(driver, device, ib, response)
  local supportedFanModes
  if ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_LOW_MED_HIGH then
    supportedFanModes = {
      capabilities.fanMode.fanMode.off.NAME,
      capabilities.fanMode.fanMode.low.NAME,
      capabilities.fanMode.fanMode.medium.NAME,
      capabilities.fanMode.fanMode.high.NAME
    }
  elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_LOW_HIGH then
    supportedFanModes = {
      capabilities.fanMode.fanMode.off.NAME,
      capabilities.fanMode.fanMode.low.NAME,
      capabilities.fanMode.fanMode.high.NAME
    }
  elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_LOW_MED_HIGH_AUTO then
    supportedFanModes = {
      capabilities.fanMode.fanMode.off.NAME,
      capabilities.fanMode.fanMode.low.NAME,
      capabilities.fanMode.fanMode.medium.NAME,
      capabilities.fanMode.fanMode.high.NAME,
      capabilities.fanMode.fanMode.auto.NAME
    }
  elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_LOW_HIGH_AUTO then
    supportedFanModes = {
      capabilities.fanMode.fanMode.off.NAME,
      capabilities.fanMode.fanMode.low.NAME,
      capabilities.fanMode.fanMode.high.NAME,
      capabilities.fanMode.fanMode.auto.NAME
    }
  elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_HIGH_AUTO then
    supportedFanModes = {
      capabilities.fanMode.fanMode.off.NAME,
      capabilities.fanMode.fanMode.high.NAME,
      capabilities.fanMode.fanMode.auto.NAME
    }
  else
    supportedFanModes = {
      capabilities.fanMode.fanMode.off.NAME,
      capabilities.fanMode.fanMode.high.NAME
    }
  end
  local event = capabilities.fanMode.supportedFanModes(supportedFanModes, {visibility = {displayed = false}})
  device:emit_event_for_endpoint(ib.endpoint_id, event)
end

local function fan_speed_percent_attr_handler(driver, device, ib, response)
  if ib.data.value == nil then
    return
  end
  local speed = utils.clamp_value(ib.data.value, 0, 100)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.fanSpeedPercent.percent(speed))
end

local function wind_support_handler(driver, device, ib, response)
  local supported_wind_modes = {capabilities.windMode.windMode.noWind.NAME}
  for mode, wind_mode in pairs(WIND_MODE_MAP) do
    if ((ib.data.value >> mode) & 1) > 0 then
      table.insert(supported_wind_modes, wind_mode.NAME)
    end
  end
  local event = capabilities.windMode.supportedWindModes(supported_wind_modes, {visibility = {displayed = false}})
  device:emit_event_for_endpoint(ib.endpoint_id, event)
end

local function wind_setting_handler(driver, device, ib, response)
  for index, wind_mode in pairs(WIND_MODE_MAP) do
    if ((ib.data.value >> index) & 1) > 0 then
      device:emit_event_for_endpoint(ib.endpoint_id, wind_mode())
      return
    end
  end
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.windMode.windMode.noWind())
end

local function hepa_filter_condition_handler(driver, device, ib, response)
  local component = device.profile.components["hepaFilter"]
  local condition = ib.data.value
  device:emit_component_event(component, capabilities.filterState.filterLifeRemaining(condition))
end

local function hepa_filter_change_indication_handler(driver, device, ib, response)
  local component = device.profile.components["hepaFilter"]
  if ib.data.value == clusters.HepaFilterMonitoring.attributes.ChangeIndication.OK then
    device:emit_component_event(component, capabilities.filterStatus.filterStatus.normal())
  elseif ib.data.value == clusters.HepaFilterMonitoring.attributes.ChangeIndication.WARNING then
    device:emit_component_event(component, capabilities.filterStatus.filterStatus.normal())
  elseif ib.data.value == clusters.HepaFilterMonitoring.attributes.ChangeIndication.CRITICAL then
    device:emit_component_event(component, capabilities.filterStatus.filterStatus.replace())
  end
end

local function activated_carbon_filter_condition_handler(driver, device, ib, response)
  local component = device.profile.components["activatedCarbonFilter"]
  local condition = ib.data.value
  device:emit_component_event(component, capabilities.filterState.filterLifeRemaining(condition))
end

local function activated_carbon_filter_change_indication_handler(driver, device, ib, response)
  local component = device.profile.components["activatedCarbonFilter"]
  if ib.data.value == clusters.ActivatedCarbonFilterMonitoring.attributes.ChangeIndication.OK then
    device:emit_component_event(component, capabilities.filterStatus.filterStatus.normal())
  elseif ib.data.value == clusters.ActivatedCarbonFilterMonitoring.attributes.ChangeIndication.WARNING then
    device:emit_component_event(component, capabilities.filterStatus.filterStatus.normal())
  elseif ib.data.value == clusters.ActivatedCarbonFilterMonitoring.attributes.ChangeIndication.CRITICAL then
    device:emit_component_event(component, capabilities.filterStatus.filterStatus.replace())
  end
end

local function on_off_attr_handler(driver, device, ib, response)
  local component = device.profile.components["light"]
  if ib.data.value then
    device:emit_component_event(component, capabilities.switch.switch.on())
  else
    device:emit_component_event(component, capabilities.switch.switch.off())
  end
end

-- Capability Handlers --
local function set_fan_mode(driver, device, cmd)
  local fan_mode_id
  if cmd.args.fanMode == capabilities.fanMode.fanMode.low.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.LOW
  elseif cmd.args.fanMode == capabilities.fanMode.fanMode.medium.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.MEDIUM
  elseif cmd.args.fanMode == capabilities.fanMode.fanMode.high.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.HIGH
  elseif cmd.args.fanMode == capabilities.fanMode.fanMode.auto.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.AUTO
  else
    fan_mode_id = clusters.FanControl.attributes.FanMode.OFF
  end
  if fan_mode_id then
    device:send(clusters.FanControl.attributes.FanMode:write(device, device:component_to_endpoint(cmd.component), fan_mode_id))
  end
end

local function set_fan_speed_percent(driver, device, cmd)
  local speed = math.floor(cmd.args.percent)
  device:send(clusters.FanControl.attributes.PercentSetting:write(device, device:component_to_endpoint(cmd.component), speed))
end

local function set_wind_mode(driver, device, cmd)
  local wind_mode = 0
  if cmd.args.windMode == capabilities.windMode.windMode.sleepWind.NAME then
    wind_mode = clusters.FanControl.types.WindSupportMask.SLEEP_WIND
  elseif cmd.args.windMode == capabilities.windMode.windMode.naturalWind.NAME then
    wind_mode = clusters.FanControl.types.WindSupportMask.NATURAL_WIND
  end
  device:send(clusters.FanControl.attributes.WindSetting:write(device, device:component_to_endpoint(cmd.component), wind_mode))
end

local function handle_switch_on(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local req = clusters.OnOff.server.commands.On(device, endpoint_id)
  device:send(req)
end

local function handle_switch_off(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local req = clusters.OnOff.server.commands.Off(device, endpoint_id)
  device:send(req)
end

local matter_extractor_hood_handler = {
  NAME = "matter-extractor-hood",
  lifecycle_handlers = {
    init = device_init,
    added = device_added
  },
  matter_handlers = {
    attr = {
      [clusters.OnOff.ID] = {
        [clusters.OnOff.attributes.OnOff.ID] = on_off_attr_handler,
      },
      [clusters.HepaFilterMonitoring.ID] = {
        [clusters.HepaFilterMonitoring.attributes.Condition.ID] = hepa_filter_condition_handler,
        [clusters.HepaFilterMonitoring.attributes.ChangeIndication.ID] = hepa_filter_change_indication_handler
      },
      [clusters.ActivatedCarbonFilterMonitoring.ID] = {
        [clusters.ActivatedCarbonFilterMonitoring.attributes.Condition.ID] = activated_carbon_filter_condition_handler,
        [clusters.ActivatedCarbonFilterMonitoring.attributes.ChangeIndication.ID] = activated_carbon_filter_change_indication_handler
      },
      [clusters.FanControl.ID] = {
        [clusters.FanControl.attributes.FanModeSequence.ID] = fan_mode_sequence_handler,
        [clusters.FanControl.attributes.FanMode.ID] = fan_mode_handler,
        [clusters.FanControl.attributes.PercentCurrent.ID] = fan_speed_percent_attr_handler,
        [clusters.FanControl.attributes.WindSupport.ID] = wind_support_handler,
        [clusters.FanControl.attributes.WindSetting.ID] = wind_setting_handler
      },
    }
  },
  capability_handlers = {
    [capabilities.fanMode.ID] = {
      [capabilities.fanMode.commands.setFanMode.NAME] = set_fan_mode
    },
    [capabilities.fanSpeedPercent.ID] = {
      [capabilities.fanSpeedPercent.commands.setPercent.NAME] = set_fan_speed_percent
    },
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = handle_switch_on,
      [capabilities.switch.commands.off.NAME] = handle_switch_off,
    },
    [capabilities.windMode.ID] = {
      [capabilities.windMode.commands.setWindMode.NAME] = set_wind_mode
    }
  },
  can_handle = is_matter_extractor_hood
}

return matter_extractor_hood_handler
