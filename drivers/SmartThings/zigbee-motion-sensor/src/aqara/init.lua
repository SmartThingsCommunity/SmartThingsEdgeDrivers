local capabilities = require "st.capabilities"
local zcl_commands = require "st.zigbee.zcl.global_commands"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local aqara_utils = require "aqara/aqara_utils"

local PowerConfiguration = clusters.PowerConfiguration

local detectionFrequency = capabilities["stse.detectionFrequency"]
local detectionFrequencyCommandName = "setDetectionFrequency"

local MOTION_ILLUMINANCE_ATTRIBUTE_ID = 0x0112
local FREQUENCY_ATTRIBUTE_ID = 0x0102

local MOTION_DETECTED_UINT32 = 65536

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

local function motion_illuminance_attr_handler(driver, device, value, zb_rx)
  -- The low 16 bits for Illuminance
  -- The high 16 bits for Motion Detection
  local raw_value = value.value
  if raw_value >= MOTION_DETECTED_UINT32 then
    aqara_utils.motion_detected(device)
  end

  local lux = raw_value - MOTION_DETECTED_UINT32
  device:emit_event(capabilities.illuminanceMeasurement.illuminance(lux))
end

local function write_attr_res_handler(driver, device, zb_rx)
  local key, value = aqara_utils.get_pref_changed_field(device)
  if key == aqara_utils.PREF_FREQUENCY_KEY then
    -- reset key
    aqara_utils.set_pref_changed_field(device, '', 0)

    -- for unoccupied timer
    device:set_field(aqara_utils.PREF_FREQUENCY_KEY, value, { persist = true })
    -- update ui
    device:emit_event(detectionFrequency.detectionFrequency(value))
  end
end

local function detection_frequency_capability_handler(driver, device, command)
  local frequency = command.args.frequency
  -- store key
  aqara_utils.set_pref_changed_field(device, aqara_utils.PREF_FREQUENCY_KEY, frequency)
  -- write
  device:send(cluster_base.write_manufacturer_specific_attribute(device, aqara_utils.PRIVATE_CLUSTER_ID,
    FREQUENCY_ATTRIBUTE_ID,
    aqara_utils.MFG_CODE, data_types.Uint8, frequency))
end

local function added_handler(self, device)
  device:emit_event(capabilities.motionSensor.motion.inactive())
  device:emit_event(capabilities.illuminanceMeasurement.illuminance(0))
  device:emit_event(detectionFrequency.detectionFrequency(aqara_utils.PREF_FREQUENCY_VALUE_DEFAULT))
  device:emit_event(capabilities.battery.battery(100))

  device:send(cluster_base.write_manufacturer_specific_attribute(device, aqara_utils.PRIVATE_CLUSTER_ID,
    aqara_utils.PRIVATE_ATTRIBUTE_ID,
    aqara_utils.MFG_CODE, data_types.Uint8, 1))
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
    added = added_handler
  },
  capability_handlers = {
    [detectionFrequency.ID] = {
      [detectionFrequencyCommandName] = detection_frequency_capability_handler
    }
  },
  zigbee_handlers = {
    global = {
      [aqara_utils.PRIVATE_CLUSTER_ID] = {
        [zcl_commands.WriteAttributeResponse.ID] = write_attr_res_handler
      }
    },
    attr = {
      [aqara_utils.PRIVATE_CLUSTER_ID] = {
        [MOTION_ILLUMINANCE_ATTRIBUTE_ID] = motion_illuminance_attr_handler
      }
    }
  },
  sub_drivers = {
    require("aqara.high-precision-motion")
  },
  can_handle = is_aqara_products
}

return aqara_motion_handler
