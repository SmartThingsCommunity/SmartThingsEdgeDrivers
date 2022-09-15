local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"

local IlluminanceMeasurement = clusters.IlluminanceMeasurement
local PowerConfiguration = clusters.PowerConfiguration

local FINGERPRINTS = {
  { mfr = "LUMI", model = "lumi.sen_ill.agl01" }
}

local configuration = {
  {
    cluster = IlluminanceMeasurement.ID,
    attribute = IlluminanceMeasurement.attributes.MeasuredValue.ID,
    minimum_interval = 5,
    maximum_interval = 3600,
    data_type = IlluminanceMeasurement.attributes.MeasuredValue.base_type,
    reportable_change = 10
  },
  {
    cluster = PowerConfiguration.ID,
    attribute = PowerConfiguration.attributes.BatteryVoltage.ID,
    minimum_interval = 30,
    maximum_interval = 3600,
    data_type = PowerConfiguration.attributes.BatteryVoltage.base_type,
    reportable_change = 1
  }
}

local is_aqara_products = function(opts, driver, device)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function device_init(driver, device)
  battery_defaults.build_linear_voltage_init(2.6, 3.0)(driver, device)

  if configuration ~= nil then
    for _, attribute in ipairs(configuration) do
      device:add_configured_attribute(attribute)
      device:add_monitored_attribute(attribute)
    end
  end
end

local function added_handler(self, device)
  device:emit_event(capabilities.illuminanceMeasurement.illuminance(0))
  device:emit_event(capabilities.battery.battery(100))
end

local aqara_illuminance_handler = {
  NAME = "Aqara Illuminance Handler",
  lifecycle_handlers = {
    init = device_init,
    added = added_handler
  },
  can_handle = is_aqara_products
}

return aqara_illuminance_handler
