local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local utils = require "st.utils"
local Thermostat = clusters.Thermostat
local PowerConfiguration = clusters.PowerConfiguration
local PowerSource = capabilities.powerSource
local Battery = capabilities.battery
local ThermostatMode = capabilities.thermostatMode

local BAT_MIN = 24.0
local BAT_MAX = 32.0

local POPP_DANFOSS_THERMOSTAT_FINGERPRINTS = {
  { mfr = "D5X84YU", model = "eT093WRO" },
  { mfr = "Danfoss", model = "eTRV0100" }
}

local is_popp_danfoss_thermostat = function(opts, driver, device)
  for _, fingerprint in ipairs(POPP_DANFOSS_THERMOSTAT_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local thermostat_heating_setpoint_handler = function(driver, device, value)
  device:emit_event(capabilities.thermostatHeatingSetpoint.heatingSetpoint({value = value.value/100.0, unit = "C"}))
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

local do_configure = function(self, device)
  device:configure()
  device:send(PowerConfiguration.attributes.BatteryVoltage:configure_reporting(device, 30, 21600, 1))
end

local info_changed = function(self, device)
  device:emit_event(ThermostatMode.supportedThermostatModes({"heat"}))
end

local popp_danfoss_thermostat = {
  NAME = "POPP Danfoss Thermostat Handler",
  zigbee_handlers = {
    attr = {
      [Thermostat.ID] = {
        [Thermostat.attributes.OccupiedHeatingSetpoint.ID] = thermostat_heating_setpoint_handler
      },
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryVoltage.ID] = battery_voltage_handler
      }
    }
  },
  lifecycle_handlers = {
    doConfigure = do_configure,
    infoChanged = info_changed
  },
  can_handle = is_popp_danfoss_thermostat
}

return popp_danfoss_thermostat