-- Copyright 2023 SmartThings
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

local MatterDriver = require "st.matter.driver"
local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"

local log = require "log"
local utils = require "st.utils"

local REFRIGERATOR_DEVICE_TYPE_ID = 0x0070
local ENDPOINT_TO_COMPONENT_MAP = "__endpoint_to_component"

local refrigeratorAndTccModeId = "spacewonder52282.refrigeratorAndTccMode"
local refrigeratorAndTccMode = capabilities[refrigeratorAndTccModeId]

local function endpoint_to_component(device, ep)
  local map = device:get_field(ENDPOINT_TO_COMPONENT_MAP) or {}
  if map[ep] and device.profile.components[map[ep]] then
    return map[ep]
  end
  return "main"
end

local function component_to_endpoint(device, component_name)
  local map = device:get_field(ENDPOINT_TO_COMPONENT_MAP) or {}
  for ep, component in pairs(map) do
    if component == component_name then return ep end
  end
end

local function device_init(driver, device)
  device:subscribe()
  device:set_endpoint_to_component_fn(endpoint_to_component)
  device:set_component_to_endpoint_fn(component_to_endpoint)
end

local function device_added(driver, device)
  local cabinet_eps = device:get_endpoints(clusters.TemperatureMeasurement.ID)
  if #cabinet_eps > 1 then
    local endpoint_to_component_map = { -- This is just a guess for now
      [cabinet_eps[1]] = "refrigerator",
      [cabinet_eps[2]] = "freezer"
    }
    device:set_field(ENDPOINT_TO_COMPONENT_MAP, endpoint_to_component_map, {persist = true})
  end
end

-- Matter Handlers --
local function is_matter_refrigerator(opts, driver, device)
  for _, ep in ipairs(device.endpoints) do
    for _, dt in ipairs(ep.device_types) do
      if dt.device_type_id == REFRIGERATOR_DEVICE_TYPE_ID then
        return true
      end
    end
  end
  return false
end

local function refrigerator_tcc_mode_attr_handler(driver, device, ib, response)
  log.info_with({ hub_logs = true },
  string.format("refrigerator_tcc_mode_attr_handler currentMode: %s", ib.data.value))

  local current_mode=math.floor(ib.data.value)
  if current_mode==0 then
    device:emit_event_for_endpoint(ib.endpoint_id, refrigeratorAndTccMode.refrigeratorAndTccMode.rapidCool())
  elseif current_mode==1 then
    device:emit_event_for_endpoint(ib.endpoint_id, refrigeratorAndTccMode.refrigeratorAndTccMode.rapidFreeze())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, refrigeratorAndTccMode.refrigeratorAndTccMode.rapidCool())
  end
end

local function refrigerator_alarm_attr_handler(driver, device, ib, response)
  if ib.data.value & clusters.RefrigeratorAlarm.types.AlarmMap.DOOR_OPEN > 0 then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.contactSensor.contact.open())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.contactSensor.contact.closed())
  end
end

local function temp_event_handler(driver, device, ib, response)
  log.info_with({ hub_logs = true },
  string.format("temp_event_handler: %s", ib.data.value))

  local temp = 0
  local unit = "C"
  if ib.data.value==nil then
    temp = 0
  else
    temp = ib.data.value / 100.0
  end
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.temperatureMeasurement.temperature({value = temp, unit = unit}))
end

-- Capability Handlers --
local function handle_refrigerator_tcc_mode(driver, device, cmd)
  log.info_with({ hub_logs = true },
  string.format("handle_refrigerator_tcc_mode currentMode: %s", cmd.args.level))

  if cmd.args.level==refrigeratorAndTccMode.refrigeratorAndTccMode.rapidCool.NAME then
    device:send(clusters.RefrigeratorAndTemperatureControlledCabinetMode.commands.ChangeToMode(device, 1, 0))
  elseif cmd.args.level==refrigeratorAndTccMode.refrigeratorAndTccMode.rapidFreeze.NAME then
    device:send(clusters.RefrigeratorAndTemperatureControlledCabinetMode.commands.ChangeToMode(device, 1, 1))
  else
    device:send(clusters.RefrigeratorAndTemperatureControlledCabinetMode.commands.ChangeToMode(device, 1, 0))
  end
end

local matter_refrigerator_handler = {
  NAME = "matter-refrigerator",
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
  },
  matter_handlers = {
    attr = {
      [clusters.RefrigeratorAndTemperatureControlledCabinetMode.ID] = {
        [clusters.RefrigeratorAndTemperatureControlledCabinetMode.attributes.CurrentMode.ID] = refrigerator_tcc_mode_attr_handler,
      },
      [clusters.RefrigeratorAlarm.ID] = {
        [clusters.RefrigeratorAlarm.attributes.State.ID] = refrigerator_alarm_attr_handler
      },
      [clusters.TemperatureMeasurement.ID] = {
        [clusters.TemperatureMeasurement.attributes.MeasuredValue.ID] = temp_event_handler,
      },
    }
  },
  capability_handlers = {
    [refrigeratorAndTccModeId] = {
      [refrigeratorAndTccMode.commands.setRefrigeratorAndTccMode.NAME] = handle_refrigerator_tcc_mode,
    },
  },
  can_handle = is_matter_refrigerator,
}

return matter_refrigerator_handler
