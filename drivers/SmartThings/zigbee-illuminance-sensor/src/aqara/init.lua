local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local zcl_commands = require "st.zigbee.zcl.global_commands"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"

local IlluminanceMeasurement = clusters.IlluminanceMeasurement
local PowerConfiguration = clusters.PowerConfiguration

local detectionFrequency = capabilities["stse.detectionFrequency"]
local setDetectionFrequencyCommandName = "setDetectionFrequency"

local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID = 0x0009
local MFG_CODE = 0x115F

local FREQUENCY_ATTRIBUTE_ID = 0x0000
local FREQUENCY_DEFAULT_VALUE = 5
local FREQUENCY_PREF = "frequencyPref"

local FINGERPRINTS = {
  { mfr = "LUMI", model = "lumi.sen_ill.agl01" }
}

local configuration = {
  {
    cluster = IlluminanceMeasurement.ID,
    attribute = IlluminanceMeasurement.attributes.MeasuredValue.ID,
    minimum_interval = 3600,
    maximum_interval = 7200,
    data_type = IlluminanceMeasurement.attributes.MeasuredValue.base_type,
    reportable_change = 1
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

local function is_aqara_products(opts, driver, device)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function detection_frequency_capability_handler(driver, device, command)
  local frequency = command.args.frequency
  device:set_field(FREQUENCY_PREF, frequency, { persist = true })
  device:send(cluster_base.write_manufacturer_specific_attribute(device, PRIVATE_CLUSTER_ID, FREQUENCY_ATTRIBUTE_ID,
    MFG_CODE, data_types.Uint16, frequency))
end

local function write_attr_res_handler(driver, device, zb_rx)
  local value = device:get_field(FREQUENCY_PREF) or FREQUENCY_DEFAULT_VALUE
  device:emit_event(detectionFrequency.detectionFrequency(value, {visibility = {displayed = false}}))
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
  device:emit_event(detectionFrequency.detectionFrequency(FREQUENCY_DEFAULT_VALUE, {visibility = {displayed = false}}))
  device:emit_event(capabilities.battery.battery(100))

  device:send(cluster_base.write_manufacturer_specific_attribute(device, PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID,
    MFG_CODE, data_types.Uint8, 1))
end

local aqara_illuminance_handler = {
  NAME = "Aqara Illuminance Handler",
  lifecycle_handlers = {
    init = device_init,
    added = added_handler
  },
  capability_handlers = {
    [detectionFrequency.ID] = {
      [setDetectionFrequencyCommandName] = detection_frequency_capability_handler,
    }
  },
  zigbee_handlers = {
    global = {
      [PRIVATE_CLUSTER_ID] = {
        [zcl_commands.WriteAttributeResponse.ID] = write_attr_res_handler
      }
    }
  },
  can_handle = is_aqara_products
}

return aqara_illuminance_handler
