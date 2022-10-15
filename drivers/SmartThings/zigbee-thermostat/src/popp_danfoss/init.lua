local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local PowerConfiguration = clusters.PowerConfiguration
local ThermostatMode = capabilities.thermostatMode
local Thermostat = clusters.Thermostat

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

local supported_thermostat_modes_handler = function(driver, device, supported_modes)
  device:emit_event(ThermostatMode.supportedThermostatModes({"heat"}, { visibility = { displayed = false } }))
end

local popp_danfoss_thermostat = {
  NAME = "POPP Danfoss Thermostat Handler",
  zigbee_handlers = {
    attr = {
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryVoltage.ID] = battery_defaults.battery_volt_attr_handler
      },
      [Thermostat.ID] = {
        [Thermostat.attributes.ControlSequenceOfOperation.ID] = supported_thermostat_modes_handler
      }
    }
  },
  lifecycle_handlers = {
    init = battery_defaults.build_linear_voltage_init(2.4, 3.2)
  },
  can_handle = is_popp_danfoss_thermostat
}

return popp_danfoss_thermostat