local clusters = require "st.zigbee.zcl.clusters"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local PowerConfiguration = clusters.PowerConfiguration

local DANFOSS_THERMOSTAT_FINGERPRINTS = {
  { mfr = "Danfoss", model = "eTRV0100" }
}

local is_danfoss_thermostat = function(opts, driver, device)
  for _, fingerprint in ipairs(DANFOSS_THERMOSTAT_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local danfoss_thermostat = {
  NAME = "Danfoss Thermostat Handler",
  zigbee_handlers = {
    attr = {
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryVoltage.ID] = battery_defaults.battery_volt_attr_handler
      }
    }
  },
  lifecycle_handlers = {
    init = battery_defaults.build_linear_voltage_init(2.4, 3.2)
  },
  can_handle = is_danfoss_thermostat
}

return danfoss_thermostat