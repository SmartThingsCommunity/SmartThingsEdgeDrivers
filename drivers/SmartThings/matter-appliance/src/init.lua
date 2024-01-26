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

local supportedTemperatureLevels = {}

local function device_init(driver, device)
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
  log.info_with({ hub_logs = true },
    string.format("temperature_setpoint_attr_handler: %s", ib.data.value))

  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.temperatureSetpoint.temperatureSetpoint({value = ib.data.value, unit = "C"}))
end

-- TODO Create temperatureLevel
-- local function selected_temperature_level_attr_handler(driver, device, ib, response)
--   log.info_with({ hub_logs = true },
--     string.format("selected_temperature_level_attr_handler: %s", ib.data.value))

--   local temperatureLevel = ib.data.value
--   for i, tempLevel in ipairs(supportedTemperatureLevels) do
--     if i - 1 == temperatureLevel then
--       device:emit_event_for_endpoint(ib.endpoint_id, capabilities.temperatureLevel.temperatureLevel(tempLevel))
--       break
--     end
--   end
-- end

-- TODO Create temperatureLevel
-- local function supported_temperature_levels_attr_handler(driver, device, ib, response)
--   log.info_with({ hub_logs = true },
--     string.format("supported_temperature_levels_attr_handler: %s", ib.data.value))

--   supportedTemperatureLevels = {}
--   for _, tempLevel in ipairs(ib.data.elements) do
--     table.insert(supportedTemperatureLevels, tempLevel.value)
--   end
--   device:emit_event_for_endpoint(ib.endpoint_id, capabilities.temperatureLevel.supportedTemperatureLevels(supportedTemperatureLevels))
-- end

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
  log.info_with({ hub_logs = true },
    string.format("handle_temperature_setpoint: %s", cmd.args.setpoint))

  local ENDPOINT = 1
  device:send(clusters.TemperatureControl.commands.SetTemperature(device, ENDPOINT, cmd.args.setpoint, nil))
end

-- TODO Create temperatureLevel
-- local function handle_temperature_level(driver, device, cmd)
--   log.info_with({ hub_logs = true },
--     string.format("handle_temperature_level: %s", cmd.args.temperatureLevel))

--   local ENDPOINT = 1
--   for i, tempLevel in ipairs(supportedTemperatureLevels) do
--     if cmd.args.temperatureLevel == tempLevel then
--       device:send(clusters.TemperatureControl.commands.SetTemperature(device, ENDPOINT, nil, i - 1))
--       return
--     end
--   end
-- end

local matter_driver_template = {
  lifecycle_handlers = {
    init = device_init,
  },
  matter_handlers = {
    attr = {
      [clusters.OnOff.ID] = {
        [clusters.OnOff.attributes.OnOff.ID] = on_off_attr_handler,
      },
      [clusters.TemperatureControl.ID] = {
        [clusters.TemperatureControl.attributes.TemperatureSetpoint.ID] = temperature_setpoint_attr_handler,
      },
    }
  },
  subscribed_attributes = {
    [capabilities.switch.ID] = {
      clusters.OnOff.attributes.OnOff
    },
    [capabilities.temperatureSetpoint.ID] = {
      clusters.TemperatureControl.attributes.TemperatureSetpoint
    },
    [capabilities.dishwasherOperatingState.ID] = {
      clusters.OperationalState.attributes.OperationalState,
      clusters.OperationalState.attributes.OperationalError,
    },
    [capabilities.mode.ID] = {
      clusters.TemperatureControl.attributes.SelectedTemperatureLevel,
      clusters.TemperatureControl.attributes.SupportedTemperatureLevels,
      clusters.DishwasherMode.attributes.SupportedModes,
      clusters.DishwasherMode.attributes.CurrentMode,
      clusters.LaundryWasherMode.attributes.SupportedModes,
      clusters.LaundryWasherMode.attributes.CurrentMode,
      clusters.LaundryWasherControls.attributes.SpinSpeeds,
      clusters.LaundryWasherControls.attributes.SpinSpeedCurrent,
      clusters.RefrigeratorAndTemperatureControlledCabinetMode.attributes.SupportedModes,
      clusters.RefrigeratorAndTemperatureControlledCabinetMode.attributes.CurrentMode,
    },
    [capabilities.laundryWasherRinseMode.ID] = {
      clusters.LaundryWasherControls.attributes.NumberOfRinses,
      clusters.LaundryWasherControls.attributes.SupportedRinses,
    },
    [capabilities.washerOperatingState.ID] = {
      clusters.OperationalState.attributes.OperationalState,
      clusters.OperationalState.attributes.OperationalError,
    },
    [capabilities.contactSensor.ID] = {
      clusters.DishwasherAlarm.attributes.State,
      clusters.RefrigeratorAlarm.attributes.State,
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
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = handle_switch_on,
      [capabilities.switch.commands.off.NAME] = handle_switch_off,
    },
    [capabilities.temperatureSetpoint.ID] = {
      [capabilities.temperatureSetpoint.commands.setTemperatureSetpoint.NAME] = handle_temperature_setpoint,
    },
  },
  sub_drivers = {
    require("matter-dishwasher"),
    require("matter-laundry-washer"),
    require("matter-refrigerator"),
  }
}

local matter_driver = MatterDriver("matter-appliance", matter_driver_template)
log.info_with({hub_logs=true}, string.format("Starting %s driver, with dispatcher: %s", matter_driver.NAME, matter_driver.matter_dispatcher))
matter_driver:run()
