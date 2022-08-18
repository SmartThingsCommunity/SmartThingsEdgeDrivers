local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local zcl_commands = require "st.zigbee.zcl.global_commands"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"

local detectionFrequency = capabilities["stse.detectionFrequency"]
local detectionFrequencyId = "stse.detectionFrequency"
local detectionFrequencyCommand = "setDetectionFrequency"

local PowerConfiguration = clusters.PowerConfiguration

local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID = 0x0009
local MFG_CODE = 0x115F
local MOTION_ILLUMINANCE_ATTRIBUTE_ID = 0x0112
local FREQUENCY_ATTRIBUTE_ID = 0x0102
local FREQUENCY_DEFAULT_VALUE = 120
local UNOCCUPIED_TIMER = "unoccupiedTimer"
local CHANGED_PREF_KEY = "prefChangedKey"
local CHANGED_PREF_VALUE = "prefChangedValue"
local FREQUENCY_PREF = "frequencyPref"
local MOTION_DETECTED_VALUE = 65536

local FINGERPRINTS = {
  { mfr = "LUMI", model = "lumi.motion.agl02" }
}

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
    cluster = PRIVATE_CLUSTER_ID,
    attribute = MOTION_ILLUMINANCE_ATTRIBUTE_ID,
    minimum_interval = 30,
    maximum_interval = 3600,
    data_type = data_types.Uint32.ID,
    reportable_change = 1
  },
  {
    cluster = PRIVATE_CLUSTER_ID,
    attribute = FREQUENCY_ATTRIBUTE_ID,
    minimum_interval = 30,
    maximum_interval = 3600,
    data_type = data_types.Uint8.ID,
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

local read_custom_attribute = function(device, cluster_id, attribute)
  local message = cluster_base.read_attribute(device, data_types.ClusterId(cluster_id), attribute)
  message.body.zcl_header.frame_ctrl:set_mfg_specific()
  message.body.zcl_header.mfg_code = data_types.validate_or_build_type(MFG_CODE, data_types.Uint16, "mfg_code")
  return message
end

local write_motion_pref_attribute = function(device, cluster, attr, value)
  device:send(cluster_base.write_manufacturer_specific_attribute(device, cluster, attr, MFG_CODE,
    data_types.Uint8, value))
end

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
  device:emit_event(detectionFrequency.detectionFrequency(FREQUENCY_DEFAULT_VALUE))
  device:emit_event(capabilities.battery.battery(100))

  device:send(cluster_base.write_manufacturer_specific_attribute(device,
    PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID, MFG_CODE, data_types.Uint8, 1))

  device:send(read_custom_attribute(device, PRIVATE_CLUSTER_ID, FREQUENCY_ATTRIBUTE_ID))
end

local function motion_detected(driver, device, value, zb_rx)
  device:emit_event(capabilities.motionSensor.motion.active())

  local unoccupied_timer = device:get_field(UNOCCUPIED_TIMER)
  if unoccupied_timer then
    device.thread:cancel_timer(unoccupied_timer)
    device:set_field(UNOCCUPIED_TIMER, nil)
  end
  local detect_duration = device:get_field(FREQUENCY_PREF) or FREQUENCY_DEFAULT_VALUE
  print(detect_duration)
  local inactive_state = function()
    device:emit_event(capabilities.motionSensor.motion.inactive())
  end
  unoccupied_timer = device.thread:call_with_delay(detect_duration, inactive_state)
  device:set_field(UNOCCUPIED_TIMER, unoccupied_timer)
end

local function motion_illuminance_attr_handler(driver, device, value, zb_rx)
  -- The low 16 bits for Illuminance
  -- The high 16 bits for Motion Detection

  if value.value > MOTION_DETECTED_VALUE then
    -- motion detected

    motion_detected(driver, device, value, zb_rx)

    local lux = value.value - MOTION_DETECTED_VALUE
    device:emit_event(capabilities.illuminanceMeasurement.illuminance(lux))
  end
end

local function detection_frequency_handler(driver, device, command)
  local frequency = command.args.frequency
  device:set_field(CHANGED_PREF_KEY, FREQUENCY_PREF)
  device:set_field(CHANGED_PREF_VALUE, frequency)
  write_motion_pref_attribute(device, PRIVATE_CLUSTER_ID, FREQUENCY_ATTRIBUTE_ID, frequency)
end

local function frequency_attr_handler(driver, device, value, zb_rx)
  local frequency = value.value
  device:set_field(FREQUENCY_PREF, frequency)
  device:emit_event(detectionFrequency.detectionFrequency(frequency))
end

local function write_attr_res_handler(driver, device, zb_rx)
  -- write attribute response for prefs
  local key = device:get_field(CHANGED_PREF_KEY) or ''
  local value = device:get_field(CHANGED_PREF_VALUE) or 0
  if key == FREQUENCY_PREF then
    -- for unoccupied timer
    device:set_field(FREQUENCY_PREF, value)
    -- update ui
    device:emit_event(detectionFrequency.detectionFrequency(value))
  end
end

local aqara_motion_handler = {
  NAME = "Aqara Motion Handler",
  lifecycle_handlers = {
    init = device_init,
    added = added_handler
  },
  capability_handlers = {
    [detectionFrequencyId] = {
      [detectionFrequencyCommand] = detection_frequency_handler,
    }
  },
  zigbee_handlers = {
    global = {
      [PRIVATE_CLUSTER_ID] = {
        [zcl_commands.WriteAttributeResponse.ID] = write_attr_res_handler
      }
    },
    attr = {
      [PRIVATE_CLUSTER_ID] = {
        -- Motion Sensor T1
        [MOTION_ILLUMINANCE_ATTRIBUTE_ID] = motion_illuminance_attr_handler,
        -- Prefs
        [FREQUENCY_ATTRIBUTE_ID] = frequency_attr_handler
      }
    }
  },
  can_handle = is_aqara_products
}

return aqara_motion_handler
