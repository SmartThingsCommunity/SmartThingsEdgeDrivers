local capabilities = require "st.capabilities"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"

local aqara_utils = {}

local detectionFrequency = capabilities["stse.detectionFrequency"]
local detectionFrequencyId = "stse.detectionFrequency"
local detectionFrequencyCommand = "setDetectionFrequency"

local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID = 0x0009
local MFG_CODE = 0x115F
local FREQUENCY_ATTRIBUTE_ID = 0x0102

local UNOCCUPIED_TIMER = "unoccupiedTimer"

local PREF_CHANGED_KEY = "prefChangedKey"
local PREF_CHANGED_VALUE = "prefChangedValue"
local PREF_FREQUENCY_KEY = "prefFrequency"
local PREF_FREQUENCY_VALUE_DEFAULT = 60

local function custom_attribute(device, cluster_id, attribute_id)
  local message = cluster_base.read_attribute(device, data_types.ClusterId(cluster_id), attribute_id)
  message.body.zcl_header.frame_ctrl:set_mfg_specific()
  message.body.zcl_header.mfg_code = data_types.validate_or_build_type(MFG_CODE, data_types.Uint16, "mfg_code")
  return message
end

local function read_custom_attribute(device, attribute_id)
  device:send(custom_attribute(device, PRIVATE_CLUSTER_ID, attribute_id))
end

local function write_custom_attribute(device, attribute_id, value)
  device:send(cluster_base.write_manufacturer_specific_attribute(device, PRIVATE_CLUSTER_ID, attribute_id, MFG_CODE,
    data_types.Uint8, value))
end

local function enable_custom_cluster_attribute(device)
  device:send(cluster_base.write_manufacturer_specific_attribute(device,
    PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID, MFG_CODE, data_types.Uint8, 1))
end

local function motion_detected(driver, device, value, zb_rx)
  device:emit_event(capabilities.motionSensor.motion.active())

  local unoccupied_timer = device:get_field(UNOCCUPIED_TIMER)
  if unoccupied_timer then
    device.thread:cancel_timer(unoccupied_timer)
    device:set_field(UNOCCUPIED_TIMER, nil)
  end

  local detect_duration = device:get_field(PREF_FREQUENCY_KEY) or PREF_FREQUENCY_VALUE_DEFAULT
  local inactive_state = function()
    device:emit_event(capabilities.motionSensor.motion.inactive())
  end
  unoccupied_timer = device.thread:call_with_delay(detect_duration, inactive_state)
  device:set_field(UNOCCUPIED_TIMER, unoccupied_timer)
end

local function get_pref_changed_field(device)
  local key = device:get_field(PREF_CHANGED_KEY) or ''
  local value = device:get_field(PREF_CHANGED_VALUE) or 0
  return key, value
end

local function set_pref_changed_field(device, key, value)
  device:set_field(PREF_CHANGED_KEY, key)
  device:set_field(PREF_CHANGED_VALUE, value)
end

local function set_detection_frequency(device, value)
  -- for unoccupied timer
  device:set_field(PREF_FREQUENCY_KEY, value, { persist = true })
  -- update ui
  device:emit_event(detectionFrequency.detectionFrequency(value))
end

local function detection_frequency_res_handler(device)
  -- detection frequency
  local key, value = get_pref_changed_field(device)
  if key == PREF_FREQUENCY_KEY then
    set_detection_frequency(device, value)
  end
end

aqara_utils.detectionFrequency = detectionFrequency
aqara_utils.detectionFrequencyId = detectionFrequencyId
aqara_utils.detectionFrequencyCommand = detectionFrequencyCommand
aqara_utils.PRIVATE_CLUSTER_ID = PRIVATE_CLUSTER_ID
aqara_utils.PRIVATE_ATTRIBUTE_ID = PRIVATE_ATTRIBUTE_ID
aqara_utils.MFG_CODE = MFG_CODE
aqara_utils.FREQUENCY_ATTRIBUTE_ID = FREQUENCY_ATTRIBUTE_ID
aqara_utils.PREF_CHANGED_KEY = PREF_CHANGED_KEY
aqara_utils.PREF_CHANGED_VALUE = PREF_CHANGED_VALUE
aqara_utils.PREF_FREQUENCY_KEY = PREF_FREQUENCY_KEY
aqara_utils.PREF_FREQUENCY_VALUE_DEFAULT = PREF_FREQUENCY_VALUE_DEFAULT
aqara_utils.read_custom_attribute = read_custom_attribute
aqara_utils.write_custom_attribute = write_custom_attribute
aqara_utils.enable_custom_cluster_attribute = enable_custom_cluster_attribute
aqara_utils.motion_detected = motion_detected
aqara_utils.get_pref_changed_field = get_pref_changed_field
aqara_utils.set_pref_changed_field = set_pref_changed_field
aqara_utils.set_detection_frequency = set_detection_frequency
aqara_utils.detection_frequency_res_handler = detection_frequency_res_handler

return aqara_utils
