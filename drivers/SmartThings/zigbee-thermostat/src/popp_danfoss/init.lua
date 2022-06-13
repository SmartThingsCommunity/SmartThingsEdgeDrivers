local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local utils = require "st.utils"
local Thermostat = clusters.Thermostat
local PowerConfiguration = clusters.PowerConfiguration
local PowerSource = capabilities.powerSource
local Battery = capabilities.battery
local ThermostatMode = capabilities.thermostatMode
local ThermostatHeatingSetpoint = capabilities.thermostatHeatingSetpoint
local ThermostatSystemMode = Thermostat.attributes.SystemMode

local DEFAULT_MIN_SETPOINT = 4.0
local DEFAULT_MAX_SETPOINT = 35.0

local BAT_MIN = 24.0
local BAT_MAX = 32.0

local POPP_THERMOSTAT_FINGERPRINTS = {
  { mfr = "D5X84YU", model = "eT093WRO" },
  { mfr = "Danfoss", model = "eTRV0100" }
}

local is_popp_thermostat = function(opts, driver, device)
  for _, fingerprint in ipairs(POPP_THERMOSTAT_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local supported_thermostat_mode_handler = function(driver, device, supported_modes)
  device:emit_event(ThermostatMode.supportedThermostatModes({"heat"}))
end

local thermostat_heating_setpoint_handler = function(driver, device, value)
  device:emit_event(capabilities.thermostatHeatingSetpoint.heatingSetpoint({value = value.value/100.0, unit = "C"}))
end

local function set_heating_setpoint(driver, device, command)
  local value = command.args.setpoint

  if value >= 35 then -- we got a command in fahrenheit
    value = utils.f_to_c(value)
  end

  if value >= DEFAULT_MIN_SETPOINT and value <= DEFAULT_MAX_SETPOINT then
    device:send(Thermostat.attributes.OccupiedHeatingSetpoint:write(device, value * 100))
    device:send(Thermostat.attributes.OccupiedHeatingSetpoint:read(device))
  end
end

local battery_perc_attr_handler = function(driver, device, value, zb_rx)
  device:emit_event(capabilities.battery.battery(utils.clamp_value(value.value, 0, 100)))
end

local battery_voltage_handler = function(driver, device, battery_voltage)
  if (battery_voltage.value == 0) then -- this means we're plugged in
    device:emit_event(PowerSource.powerSource.mains())
    device:emit_event(Battery.battery(100))
  else
    local perc_value = utils.round((battery_voltage.value - BAT_MIN)/(BAT_MAX - BAT_MIN) * 100)
    device:emit_event(Battery.battery(utils.clamp_value(perc_value, 0, 100)))
  end
end

local set_thermostat_mode = function(driver, device, command)
    device:send(Thermostat.attributes.SystemMode:write(device, ThermostatSystemMode.HEAT))
    device.thread:call_with_delay(2, function(d)
      device:send(Thermostat.attributes.SystemMode:read(device))
    end)
end

local do_configure = function(self, device)
  device:configure()
  device:send(PowerConfiguration.attributes.BatteryVoltage:configure_reporting(device, 30, 21600, 1))
end

local popp_danfoss_thermostat = {
  NAME = "POPP Danfoss Thermostat Handler",
  zigbee_handlers = {
    attr = {
      [Thermostat.ID] = {
        [Thermostat.attributes.ControlSequenceOfOperation.ID] = supported_thermostat_mode_handler,
        [Thermostat.attributes.OccupiedHeatingSetpoint.ID] = thermostat_heating_setpoint_handler
      },
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryPercentageRemaining.ID] = battery_perc_attr_handler
      },
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryVoltage.ID] = battery_voltage_handler
      }
    }
  },
  capability_handlers = {
    [ThermostatMode.ID] = {
      [ThermostatMode.commands.setThermostatMode.NAME] = set_thermostat_mode
    },
    [ThermostatHeatingSetpoint.ID] = {
      [ThermostatHeatingSetpoint.commands.setHeatingSetpoint.NAME] = set_heating_setpoint
    }
  },
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  can_handle = is_popp_thermostat
}

return popp_danfoss_thermostat