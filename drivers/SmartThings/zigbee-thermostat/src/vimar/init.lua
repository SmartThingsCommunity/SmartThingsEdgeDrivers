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

local device_management = require "st.zigbee.device_management"
local clusters = require "st.zigbee.zcl.clusters"
local utils = require "st.utils"
local Thermostat = clusters.Thermostat
local ThermostatControlSequence = Thermostat.attributes.ControlSequenceOfOperation
local ThermostatSystemMode = Thermostat.attributes.SystemMode
local capabilities = require "st.capabilities"
local ThermostatMode = capabilities.thermostatMode

local VIMAR_SUPPORTED_THERMOSTAT_MODES = {
  [ThermostatControlSequence.COOLING_ONLY] = {
    ThermostatMode.thermostatMode.off.NAME,
    ThermostatMode.thermostatMode.cool.NAME
  },
  [ThermostatControlSequence.HEATING_ONLY] = {
    ThermostatMode.thermostatMode.off.NAME,
    ThermostatMode.thermostatMode.heat.NAME
  }
}

local VIMAR_THERMOSTAT_MODE_MAP = {
  [ThermostatSystemMode.OFF]  = ThermostatMode.thermostatMode.off,
  [ThermostatSystemMode.COOL] = ThermostatMode.thermostatMode.cool,
  [ThermostatSystemMode.HEAT] = ThermostatMode.thermostatMode.heat,
}

local VIMAR_THERMOSTAT_FINGERPRINT = {
  mfr = "Vimar",
  model = "WheelThermostat_v1.0"
}

-- NOTE: This is a global variable to use in order to save the current thermostat profile
local VIMAR_CURRENT_PROFILE = "_vimarThermostatCurrentProfile"

local VIMAR_THERMOSTAT_HEATING_PROFILE = "thermostat-fanless-heating-no-fw"
local VIMAR_THERMOSTAT_COOLING_PROFILE = "thermostat-fanless-cooling-no-fw"


local vimar_thermostat_can_handle = function(opts, driver, device)
  return device:get_manufacturer() == VIMAR_THERMOSTAT_FINGERPRINT.mfr and
      device:get_model() == VIMAR_THERMOSTAT_FINGERPRINT.model
end

local vimar_thermostat_supported_modes_handler = function(driver, device, supported_modes)
  device:emit_event(
    ThermostatMode.supportedThermostatModes(
      VIMAR_SUPPORTED_THERMOSTAT_MODES[supported_modes.value],
      { visibility = { displayed = false } }
    )
  )
end

-- NOTE: Vimar requires (5-39) and (6-40) as maximum setpoint limits for heating and cooling, respectively.
--       The device firmare adjusts the opposite setpoint value to
--       overcome the ZigBee deadband limits of 1 degree.
--       I.E. Heating Mode --> CoolingSetpoint 40, HeatingSetpoint 20
--            Cooliing Mode --> CoolingSetpoint 25, HeatingSetpoint 5
local vimar_set_setpoint_factory = function(setpoint_attribute)
  return function(driver, device, command)
    local value = command.args.setpoint
    if (value >= 41.0) then
      value = utils.f_to_c(value)
    end
    device:send(setpoint_attribute:write(device, utils.round(value * 100)))

    device.thread:call_with_delay(2, function(d)
      device:send(setpoint_attribute:read(device))
    end)
  end
end

-- NOTE: unused attributes are not refreshed
local vimar_thermostat_do_refresh = function(self, device)
  local attributes = {
    Thermostat.attributes.LocalTemperature,
    Thermostat.attributes.ControlSequenceOfOperation,
    Thermostat.attributes.ThermostatRunningState,
    Thermostat.attributes.SystemMode
  }

  local vimar_thermostat_profile = device:get_field(VIMAR_CURRENT_PROFILE)
  if vimar_thermostat_profile == ThermostatMode.thermostatMode.heat.NAME then
    attributes[#attributes + 1] = Thermostat.attributes.OccupiedHeatingSetpoint
  elseif vimar_thermostat_profile == ThermostatMode.thermostatMode.cool.NAME then
    attributes[#attributes + 1] = Thermostat.attributes.OccupiedCoolingSetpoint
  end

  for _, attribute in pairs(attributes) do
    device:send(attribute:read(device))
  end
end

-- NOTE: Whenever the physical button for the current mode is pressed on the device, this function changes the device profile.
--       If the Thermostat is OFF, no profile change is required.
local vimar_thermostat_mode_handler = function(driver, device, thermostat_mode)
  local mode = VIMAR_THERMOSTAT_MODE_MAP[thermostat_mode.value].NAME
  -- If is a known supported mode, then apply the change
  if VIMAR_THERMOSTAT_MODE_MAP[thermostat_mode.value] then
    local vimar_thermostat_profile = device:get_field(VIMAR_CURRENT_PROFILE)
    -- HEAT: if the previous mode was cool, update profile
    if mode == ThermostatMode.thermostatMode.heat.NAME then
      if mode ~= vimar_thermostat_profile then
        device:try_update_metadata({ profile = VIMAR_THERMOSTAT_HEATING_PROFILE })
        device:set_field(VIMAR_CURRENT_PROFILE, mode)
        device.thread:call_with_delay(2, function(d)
          vimar_thermostat_do_refresh(driver, device)
        end)
      end
      -- COOL: if the previous mode was heat, update profile
    elseif mode == ThermostatMode.thermostatMode.cool.NAME then
      if mode ~= vimar_thermostat_profile then
        device:try_update_metadata({ profile = VIMAR_THERMOSTAT_COOLING_PROFILE })
        device:set_field(VIMAR_CURRENT_PROFILE, mode)
        device.thread:call_with_delay(2, function(d)
          vimar_thermostat_do_refresh(driver, device)
        end)
      end
    end
    device:emit_event(VIMAR_THERMOSTAT_MODE_MAP[thermostat_mode.value]())
  end
end

-- NOTE: override default thermostat mode map; logic is the same from the original driver
local vimar_set_thermostat_mode = function(driver, device, command)
  for zigbee_attr_val, st_cap_val in pairs(VIMAR_THERMOSTAT_MODE_MAP) do
    if command.args.mode == st_cap_val.NAME then
      device:send_to_component(command.component, Thermostat.attributes.SystemMode:write(device, zigbee_attr_val))
      device.thread:call_with_delay(1, function(d)
        device:send_to_component(command.component, Thermostat.attributes.SystemMode:read(device))
      end)
      break
    end
  end
end

-- NOTE: unused binds are not required in the configuration procedure
local vimar_thermostat_do_configure = function(self, device)
  device:send(device_management.build_bind_request(device, Thermostat.ID, self.environment_info.hub_zigbee_eui))
  -- Default mode is HEAT
  device:set_field(VIMAR_CURRENT_PROFILE, ThermostatMode.thermostatMode.heat.NAME)
  -- Read the SystemMode at first configuration so as to change the profile accordingly
  -- The profile is changed in vimar_thermostat_mode_handler function
  device:send(Thermostat.attributes.SystemMode:read(device))
end

local vimar_thermostat_subdriver = {
  NAME = "Vimar Thermostat Handler",
  zigbee_handlers = {
    attr = {
      [Thermostat.ID] = {
        [Thermostat.attributes.SystemMode.ID] = vimar_thermostat_mode_handler,
        [Thermostat.attributes.ControlSequenceOfOperation.ID] = vimar_thermostat_supported_modes_handler,
      }
    }
  },
  capability_handlers = {
    [ThermostatMode.ID] = {
      [ThermostatMode.commands.setThermostatMode.NAME] = vimar_set_thermostat_mode,
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = vimar_thermostat_do_refresh,
    },
    [capabilities.thermostatCoolingSetpoint.ID] = {
      [capabilities.thermostatCoolingSetpoint.commands.setCoolingSetpoint.NAME] = vimar_set_setpoint_factory(clusters.Thermostat.attributes.OccupiedCoolingSetpoint)
    },
    [capabilities.thermostatHeatingSetpoint.ID] = {
      [capabilities.thermostatHeatingSetpoint.commands.setHeatingSetpoint.NAME] = vimar_set_setpoint_factory(clusters.Thermostat.attributes.OccupiedHeatingSetpoint)
    }
  },
  doConfigure = vimar_thermostat_do_configure,
  can_handle = vimar_thermostat_can_handle
}

return vimar_thermostat_subdriver
