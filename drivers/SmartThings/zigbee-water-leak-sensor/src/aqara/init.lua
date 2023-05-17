local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"

local PowerConfiguration = clusters.PowerConfiguration

local MFG_CODE = 0x115F
local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID = 0x0009

local FINGERPRINTS = {
  { mfr = "LUMI", model = "lumi.flood.agl02" }
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

local function is_aqara_products(opts, driver, device)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function device_added(driver, device)
  device:emit_event(capabilities.waterSensor.water.dry())
  device:emit_event(capabilities.battery.battery(100))

  device:send(cluster_base.write_manufacturer_specific_attribute(device, PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID,
    MFG_CODE, data_types.Uint8, 1))
end

local function device_init(driver, device)
  battery_defaults.build_linear_voltage_init(2.6, 3.0)(driver, device)

  for _, attribute in ipairs(CONFIGURATIONS) do
    device:add_configured_attribute(attribute)
    device:add_monitored_attribute(attribute)
  end
end

local aqara_contact_handler = {
  NAME = "Aqara water leak sensor",
  lifecycle_handlers = {
    init = device_init,
    added = device_added
  },
  can_handle = is_aqara_products
}

return aqara_contact_handler
