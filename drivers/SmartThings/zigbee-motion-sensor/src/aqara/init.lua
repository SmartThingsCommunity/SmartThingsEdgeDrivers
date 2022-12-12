local zcl_clusters = require "st.zigbee.zcl.clusters"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"

local PowerConfiguration = zcl_clusters.PowerConfiguration

local FINGERPRINTS = {
  { mfr = "LUMI", model = "lumi.motion.agl02" },
  { mfr = "LUMI", model = "lumi.motion.agl04" }
}

local CONFIGURATIONS = {
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

  for _, attribute in ipairs(CONFIGURATIONS) do
    device:add_configured_attribute(attribute)
    device:add_monitored_attribute(attribute)
  end
end

local aqara_motion_handler = {
  NAME = "Aqara Motion Handler",
  lifecycle_handlers = {
    init = device_init,
  },
  sub_drivers = {
    require("aqara.motion-illuminance"),
    require("aqara.high-precision-motion")
  },
  can_handle = is_aqara_products
}

return aqara_motion_handler
