-- Copyright 2025 SmartThings
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
local common_utils = require "common-utils"
local log = require "log"
local version = require "version"

if version.api < 10 then
  clusters.ActivatedCarbonFilterMonitoring = require "ActivatedCarbonFilterMonitoring"
  clusters.DishwasherAlarm = require "DishwasherAlarm"
  clusters.DishwasherMode = require "DishwasherMode"
  clusters.HepaFilterMonitoring = require "HepaFilterMonitoring"
  clusters.LaundryWasherControls = require "LaundryWasherControls"
  clusters.LaundryWasherMode = require "LaundryWasherMode"
  clusters.OperationalState = require "OperationalState"
  clusters.RefrigeratorAlarm = require "RefrigeratorAlarm"
  clusters.RefrigeratorAndTemperatureControlledCabinetMode = require "RefrigeratorAndTemperatureControlledCabinetMode"
  clusters.TemperatureControl = require "TemperatureControl"
end

if version.api < 11 then
  clusters.MicrowaveOvenControl = require "MicrowaveOvenControl"
  clusters.MicrowaveOvenMode = require "MicrowaveOvenMode"
end

if version.api < 12 then
  clusters.OvenMode = require "OvenMode"
end

local subscribed_attributes = {
  [capabilities.switch.ID] = {
    clusters.OnOff.attributes.OnOff
  },
  [capabilities.temperatureSetpoint.ID] = {
    clusters.TemperatureControl.attributes.TemperatureSetpoint,
    clusters.TemperatureControl.attributes.MinTemperature,
    clusters.TemperatureControl.attributes.MaxTemperature
  },
  [capabilities.temperatureLevel.ID] = {
    clusters.TemperatureControl.attributes.SelectedTemperatureLevel,
    clusters.TemperatureControl.attributes.SupportedTemperatureLevels
  },
  [capabilities.operationalState.ID] = {
    clusters.OperationalState.attributes.AcceptedCommandList,
    clusters.OperationalState.attributes.OperationalState,
    clusters.OperationalState.attributes.OperationalError
  },
  [capabilities.mode.ID] = {
    clusters.DishwasherMode.attributes.SupportedModes,
    clusters.DishwasherMode.attributes.CurrentMode,
    clusters.LaundryWasherMode.attributes.SupportedModes,
    clusters.LaundryWasherMode.attributes.CurrentMode,
    clusters.RefrigeratorAndTemperatureControlledCabinetMode.attributes.SupportedModes,
    clusters.RefrigeratorAndTemperatureControlledCabinetMode.attributes.CurrentMode,
    clusters.MicrowaveOvenMode.attributes.CurrentMode,
    clusters.MicrowaveOvenMode.attributes.SupportedModes,
    clusters.OvenMode.attributes.SupportedModes,
    clusters.OvenMode.attributes.CurrentMode
  },
  [capabilities.laundryWasherRinseMode.ID] = {
    clusters.LaundryWasherControls.attributes.NumberOfRinses,
    clusters.LaundryWasherControls.attributes.SupportedRinses
  },
  [capabilities.laundryWasherSpinSpeed.ID] = {
    clusters.LaundryWasherControls.attributes.SpinSpeeds,
    clusters.LaundryWasherControls.attributes.SpinSpeedCurrent
  },
  [capabilities.contactSensor.ID] = {
    clusters.DishwasherAlarm.attributes.State,
    clusters.RefrigeratorAlarm.attributes.State
  },
  [capabilities.temperatureMeasurement.ID] = {
    clusters.TemperatureMeasurement.attributes.MeasuredValue
  },
  [capabilities.waterFlowAlarm.ID] = {
    clusters.DishwasherAlarm.attributes.State
  },
  [capabilities.temperatureAlarm.ID] = {
    clusters.DishwasherAlarm.attributes.State
  },
  [capabilities.fanMode.ID] = {
    clusters.FanControl.attributes.FanModeSequence,
    clusters.FanControl.attributes.FanMode
  },
  [capabilities.fanSpeedPercent.ID] = {
    clusters.FanControl.attributes.PercentCurrent
  },
  [capabilities.windMode.ID] = {
    clusters.FanControl.attributes.WindSupport,
    clusters.FanControl.attributes.WindSetting
  },
  [capabilities.filterState.ID] = {
    clusters.HepaFilterMonitoring.attributes.Condition,
    clusters.ActivatedCarbonFilterMonitoring.attributes.Condition
  },
  [capabilities.filterStatus.ID] = {
    clusters.HepaFilterMonitoring.attributes.ChangeIndication,
    clusters.ActivatedCarbonFilterMonitoring.attributes.ChangeIndication
  },
  [capabilities.cookTime.ID] = {
    clusters.MicrowaveOvenControl.attributes.MaxCookTime,
    clusters.MicrowaveOvenControl.attributes.CookTime
  }
}

local function endpoint_to_component(device, ep)
  local map = device:get_field(common_utils.COMPONENT_TO_ENDPOINT_MAP) or {}
  for component, endpoint in pairs(map) do
    if endpoint == ep then
      return component
    end
  end
  return "main"
end

local function component_to_endpoint(device, component)
  local map = device:get_field(common_utils.COMPONENT_TO_ENDPOINT_MAP) or {}
  if map[component] then
    return map[component]
  end
  return device.MATTER_DEFAULT_ENDPOINT
end

-- Lifecycle Handlers --
local function device_init(driver, device)
  common_utils.check_field_name_updates(device)
  device:subscribe()
  device:set_endpoint_to_component_fn(endpoint_to_component)
  device:set_component_to_endpoint_fn(component_to_endpoint)
end

local function info_changed(driver, device, event, args)
  --Note this is needed because device:subscribe() does not recalculate
  -- the subscribed attributes each time it is run, that only happens at init.
  -- This will change in the 0.48.x release of the lua libs.
  for cap_id, attributes in pairs(subscribed_attributes) do
    if device:supports_capability_by_id(cap_id) then
      for _, attr in ipairs(attributes) do
        device:add_subscribed_attribute(attr)
      end
    end
  end
  device:subscribe()
end

-- Matter Handlers --
local function on_off_attr_handler(driver, device, ib, response)
  if ib.data.value then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switch.switch.on())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switch.switch.off())
  end
end

local function temperature_setpoint_attr_handler(driver, device, ib, response)
  common_utils.temperature_setpoint_attr_handler(device, ib, "default")
end

local function setpoint_limit_handler(limit_field)
  return function(driver, device, ib, response)
    common_utils.setpoint_limit_handler(device, ib, limit_field, "default")
  end
end

local function selected_temperature_level_attr_handler(driver, device, ib, response)
  if not common_utils.supports_temperature_level_endpoint(device, ib.endpoint_id) then
    return
  end
  local temperatureLevel = ib.data.value
  local supportedTemperatureLevelsMap = device:get_field(common_utils.SUPPORTED_TEMPERATURE_LEVELS_MAP)
  if not supportedTemperatureLevelsMap or not supportedTemperatureLevelsMap[ib.endpoint_id] then
    return
  end
  local supportedTemperatureLevels = supportedTemperatureLevelsMap[ib.endpoint_id]
  for i, tempLevel in ipairs(supportedTemperatureLevels) do
    if i - 1 == temperatureLevel then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.temperatureLevel.temperatureLevel(tempLevel))
      break
    end
  end
end

local function supported_temperature_levels_attr_handler(driver, device, ib, response)
  if not common_utils.supports_temperature_level_endpoint(device, ib.endpoint_id) then
    return
  end
  local supportedTemperatureLevelsMap = device:get_field(common_utils.SUPPORTED_TEMPERATURE_LEVELS_MAP) or {}
  local supportedTemperatureLevels = {}
  for _, tempLevel in ipairs(ib.data.elements) do
    table.insert(supportedTemperatureLevels, tempLevel.value)
  end
  for ep = 1, ib.endpoint_id - 1 do
    if not supportedTemperatureLevelsMap[ep] then
      supportedTemperatureLevelsMap[ep] = {"Nothing"}
    end
  end
  supportedTemperatureLevelsMap[ib.endpoint_id] = supportedTemperatureLevels
  device:set_field(common_utils.SUPPORTED_TEMPERATURE_LEVELS_MAP, supportedTemperatureLevelsMap, { persist = true })
  local event = capabilities.temperatureLevel.supportedTemperatureLevels(supportedTemperatureLevels, {visibility = {displayed = false}})
  device:emit_event_for_endpoint(ib.endpoint_id, event)
end

local function temp_event_handler(driver, device, ib, response)
  local temp = ib.data.value and ib.data.value / 100.0 or 0
  local unit = "C"
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.temperatureMeasurement.temperature({value = temp, unit = unit}))
end

-- Capability Handlers --
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

local function handle_temperature_setpoint(driver, device, cmd)
  common_utils.handle_temperature_setpoint(device, cmd, "default")
end

local function handle_temperature_level(driver, device, cmd)
  local ep = device:component_to_endpoint(cmd.component)
  if not common_utils.supports_temperature_level_endpoint(device, ep) then
    return
  end
  local supportedTemperatureLevelsMap = device:get_field(common_utils.SUPPORTED_TEMPERATURE_LEVELS_MAP)
  if not supportedTemperatureLevelsMap then
    return
  end
  local supportedTemperatureLevels = supportedTemperatureLevelsMap[ep]
  for i, tempLevel in ipairs(supportedTemperatureLevels) do
    if cmd.args.temperatureLevel == tempLevel then
      device:send(clusters.TemperatureControl.commands.SetTemperature(device, ep, nil, i - 1))
      return
    end
  end
end

local matter_driver_template = {
  lifecycle_handlers = {
    init = device_init,
    infoChanged = info_changed
  },
  matter_handlers = {
    attr = {
      [clusters.OnOff.ID] = {
        [clusters.OnOff.attributes.OnOff.ID] = on_off_attr_handler
      },
      [clusters.TemperatureControl.ID] = {
        [clusters.TemperatureControl.attributes.TemperatureSetpoint.ID] = temperature_setpoint_attr_handler,
        [clusters.TemperatureControl.attributes.MaxTemperature.ID] = setpoint_limit_handler(common_utils.setpoint_limit_device_field.MAX_TEMP),
        [clusters.TemperatureControl.attributes.MinTemperature.ID] = setpoint_limit_handler(common_utils.setpoint_limit_device_field.MIN_TEMP),
        [clusters.TemperatureControl.attributes.SelectedTemperatureLevel.ID] = selected_temperature_level_attr_handler,
        [clusters.TemperatureControl.attributes.SupportedTemperatureLevels.ID] = supported_temperature_levels_attr_handler
      },
      [clusters.TemperatureMeasurement.ID] = {
        [clusters.TemperatureMeasurement.attributes.MeasuredValue.ID] = temp_event_handler
      }
    }
  },
  subscribed_attributes = subscribed_attributes,
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = handle_switch_on,
      [capabilities.switch.commands.off.NAME] = handle_switch_off
    },
    [capabilities.temperatureLevel.ID] = {
      [capabilities.temperatureLevel.commands.setTemperatureLevel.NAME] = handle_temperature_level
    },
    [capabilities.temperatureSetpoint.ID] = {
      [capabilities.temperatureSetpoint.commands.setTemperatureSetpoint.NAME] = handle_temperature_setpoint
    }
  },
  supported_capabilities = {
    capabilities.switch,
    capabilities.temperatureSetpoint,
    capabilities.temperatureLevel,
    capabilities.operationalState.ID,
    capabilities.mode,
    capabilities.laundryWasherRinseMode,
    capabilities.contactSensor,
    capabilities.temperatureMeasurement,
    capabilities.waterFlowAlarm,
    capabilities.temperatureAlarm,
    capabilities.filterState,
    capabilities.filterStatus,
    capabilities.fanMode,
    capabilities.fanSpeedPercent,
    capabilities.windMode
  },
  sub_drivers = {
    require("matter-cook-top"),
    require("matter-dishwasher"),
    require("matter-extractor-hood"),
    require("matter-laundry"),
    require("matter-microwave-oven"),
    require("matter-oven"),
    require("matter-refrigerator")
  }
}

local matter_driver = MatterDriver("matter-appliance", matter_driver_template)
log.info_with({hub_logs=true}, string.format("Starting %s driver, with dispatcher: %s", matter_driver.NAME, matter_driver.matter_dispatcher))
matter_driver:run()
