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

local ENDPOINT_TO_COMPONENT_MAP = "__endpoint_to_component"

local setpoint_limit_device_field = {
  MIN_COOL = "MIN_COOL",
  MAX_COOL = "MAX_COOL",
}

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
  local cabinet_eps = device:get_endpoints(clusters.TemperatureControl.ID)
  if #cabinet_eps > 1 then
    local endpoint_to_component_map = { -- This is just a guess for now
      [cabinet_eps[1]] = "refrigerator"
    }
    device:set_field(ENDPOINT_TO_COMPONENT_MAP, endpoint_to_component_map, {persist = true})
  end
end

-- Matter Handlers --
local function refrigerator_alarm_attr_handler(driver, device, ib, response)
  if ib.data.value & clusters.RefrigeratorAlarm.types.AlarmMap.DOOR_OPEN then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.contactSensor.contact.open())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.contactSensor.contact.closed())
  end
end

local function temp_event_handler(driver, device, ib, response)
  local temp = ib.data.value / 100.0
  local unit = "C"
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.temperatureMeasurement.temperature({value = temp, unit = unit}))
end

local function temp_setpoint_handler(driver, device, ib, response)
  local temp = ib.data.value
  local unit = "C"
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.thermostatCoolingSetpoint.coolingSetpoint({value = temp, unit = unit}))

end

local function set_setpoint()
  return function(driver, device, cmd)
    local value = cmd.args.setpoint
    if (value >= 40) then -- assume this is a fahrenheit value
      value = utils.f_to_c(value)
    end

    -- Gather cached setpoint values when considering setpoint limits
    -- Note: cached values should always exist, but defaults are chosen just in case to prevent
    -- nil operation errors, and deadband logic from triggering.
    local cached_cooling_val, cooling_setpoint = device:get_latest_state(
            cmd.component, capabilities.thermostatCoolingSetpoint.ID,
            capabilities.thermostatCoolingSetpoint.coolingSetpoint.NAME,
            100, { value = 100, unit = "C" }
    )
    if cooling_setpoint and cooling_setpoint.unit == "F" then
      cached_cooling_val = utils.f_to_c(cached_cooling_val)
    end

    local min = device:get_field(setpoint_limit_device_field.MIN_COOL) or 0
    local max = device:get_field(setpoint_limit_device_field.MAX_COOL) or 100
    if value < min or value > max then
      log.warn(string.format(
              "Invalid setpoint (%s) outside the min (%s) and the max (%s)",
              value, min, max
      ))
      device:emit_event(capabilities.thermostatCoolingSetpoint.coolingSetpoint(cooling_setpoint))
      return
    end
    local req = clusters.TemperatureControl.server.commands.SetTemperature(
            device,
            device:component_to_endpoint(cmd.component),
            value)
    device:send(req)
  end
end


local matter_driver_template = {
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
  },
  matter_handlers = {
    attr = {
      [clusters.RefrigeratorAlarm.ID] = {
        [clusters.RefrigeratorAlarm.attributes.State.ID] = refrigerator_alarm_attr_handler
      },
      [clusters.TemperatureMeasurement.ID] = {
        [clusters.TemperatureMeasurement.attributes.MeasuredValue.ID] = temp_event_handler,
      },
      [clusters.TemperatureControl.ID] = {
        [clusters.TemperatureControl.attributes.TemperatureSetpoint.ID] = temp_setpoint_handler,
      },
    }
  },
  subscribed_attributes = {
    [capabilities.contactSensor.ID] = {
      clusters.RefrigeratorAlarm.attributes.State
    },
    [capabilities.temperatureMeasurement.ID] = {
      clusters.TemperatureMeasurement.attributes.MeasuredValue
    },
    [capabilities.thermostatCoolingSetpoint.ID] = {
      clusters.TemperatureControl.attributes.TemperatureSetpoint
    },
  },
  capability_handlers = {
    [capabilities.thermostatCoolingSetpoint.ID] = {
      [capabilities.thermostatCoolingSetpoint.commands.setCoolingSetpoint.NAME] = set_setpoint()
    },
  },
}

local matter_driver = MatterDriver("matter-refrigerator", matter_driver_template)
log.info_with({hub_logs=true}, string.format("Starting %s driver, with dispatcher: %s", matter_driver.NAME, matter_driver.matter_dispatcher))
matter_driver:run()
