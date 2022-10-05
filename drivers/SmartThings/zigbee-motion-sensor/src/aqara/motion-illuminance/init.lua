local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local data_types = require "st.zigbee.data_types"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local zcl_commands = require "st.zigbee.zcl.global_commands"
local aqara_utils = require "aqara/aqara_utils"

local PowerConfiguration = clusters.PowerConfiguration

local MOTION_ILLUMINANCE_ATTRIBUTE_ID = 0x0112
local MOTION_DETECTED_UINT32 = 65536

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

  aqara_utils.enable_custom_cluster_attribute(device)
  aqara_utils.read_custom_attribute(device, aqara_utils.FREQUENCY_ATTRIBUTE_ID)
end

local function write_attr_res_handler(driver, device, zb_rx)
  aqara_utils.detection_frequency_res_handler(device)
end

local function motion_illuminance_attr_handler(driver, device, value, zb_rx)
  -- The low 16 bits for Illuminance
  -- The high 16 bits for Motion Detection

  if value.value > MOTION_DETECTED_UINT32 then
    -- motion detected
    aqara_utils.motion_detected(driver, device, value, zb_rx)

    local lux = value.value - MOTION_DETECTED_UINT32
    device:emit_event(capabilities.illuminanceMeasurement.illuminance(lux))
  end
end

local aqara_motion_illuminance_handler = {
  NAME = "Aqara Motion Illuminance Handler",
  lifecycle_handlers = {
    init = device_init,
    added = added_handler
  },
  zigbee_handlers = {
    global = {
      [aqara_utils.PRIVATE_CLUSTER_ID] = {
        [zcl_commands.WriteAttributeResponse.ID] = write_attr_res_handler
      }
    },
    attr = {
      [aqara_utils.PRIVATE_CLUSTER_ID] = {
        [MOTION_ILLUMINANCE_ATTRIBUTE_ID] = motion_illuminance_attr_handler,
      }
    }
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_model() == "lumi.motion.agl02"
  end
}

return aqara_motion_illuminance_handler
