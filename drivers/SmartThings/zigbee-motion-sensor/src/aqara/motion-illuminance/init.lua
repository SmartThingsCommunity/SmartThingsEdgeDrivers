local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local aqara_utils = require "aqara/aqara_utils"

local PowerConfiguration = clusters.PowerConfiguration

local CONFIGURATIONS = {
  {
    cluster = PowerConfiguration.ID,
    attribute = PowerConfiguration.attributes.BatteryVoltage.ID,
    minimum_interval = 30,
    maximum_interval = 3600,
    data_type = PowerConfiguration.attributes.BatteryVoltage.base_type,
    reportable_change = 1
  },
  {
    cluster = aqara_utils.PRIVATE_CLUSTER_ID,
    attribute = aqara_utils.FREQUENCY_ATTRIBUTE_ID,
    minimum_interval = 30,
    maximum_interval = 3600,
    data_type = data_types.Uint8.ID,
    reportable_change = 1
  }
}

local function device_init(driver, device)
  battery_defaults.build_linear_voltage_init(2.6, 3.0)(driver, device)

  for _, attribute in ipairs(CONFIGURATIONS) do
    device:add_configured_attribute(attribute)
    device:add_monitored_attribute(attribute)
  end
end

local function added_handler(self, device)
  device:emit_event(capabilities.motionSensor.motion.inactive())
  device:emit_event(capabilities.illuminanceMeasurement.illuminance(0))
  device:emit_event(aqara_utils.detectionFrequency.detectionFrequency(aqara_utils.PREF_FREQUENCY_VALUE_DEFAULT))
  device:emit_event(capabilities.battery.battery(100))

  device:send(cluster_base.write_manufacturer_specific_attribute(device,
    aqara_utils.PRIVATE_CLUSTER_ID, aqara_utils.PRIVATE_ATTRIBUTE_ID, aqara_utils.MFG_CODE, data_types.Uint8, 1))
  device:send(aqara_utils.read_custom_attribute(device, aqara_utils.PRIVATE_CLUSTER_ID,
    aqara_utils.FREQUENCY_ATTRIBUTE_ID))
end

local aqara_motion_handler = {
  NAME = "Aqara Motion Illuminance Handler",
  lifecycle_handlers = {
    init = device_init,
    added = added_handler
  },
  zigbee_handlers = {
    attr = {
      [aqara_utils.PRIVATE_CLUSTER_ID] = {
        [aqara_utils.MOTION_ILLUMINANCE_ATTRIBUTE_ID] = aqara_utils.motion_illuminance_attr_handler,
      }
    }
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_model() == "lumi.motion.agl02"
  end
}

return aqara_motion_handler
