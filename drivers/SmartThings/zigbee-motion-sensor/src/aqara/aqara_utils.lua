local capabilities = require "st.capabilities"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"

local aqara_utils = {}

local detectionFrequency = capabilities["stse.detectionFrequency"]
aqara_utils.detectionFrequency = detectionFrequency
local detectionFrequencyId = "stse.detectionFrequency"
aqara_utils.detectionFrequencyId = detectionFrequencyId
local detectionFrequencyCommand = "setDetectionFrequency"
aqara_utils.detectionFrequencyCommand = detectionFrequencyCommand
local sensitivityAdjustment = capabilities["stse.sensitivityAdjustment"]
aqara_utils.sensitivityAdjustment = sensitivityAdjustment
local sensitivityAdjustmentId = "stse.sensitivityAdjustment"
aqara_utils.sensitivityAdjustmentId = sensitivityAdjustmentId
local sensitivityAdjustmentCommand = "setSensitivityAdjustment"
aqara_utils.sensitivityAdjustmentCommand = sensitivityAdjustmentCommand

local PRIVATE_CLUSTER_ID = 0xFCC0
aqara_utils.PRIVATE_CLUSTER_ID = PRIVATE_CLUSTER_ID
local PRIVATE_ATTRIBUTE_ID = 0x0009
aqara_utils.PRIVATE_ATTRIBUTE_ID = PRIVATE_ATTRIBUTE_ID
local MFG_CODE = 0x115F
aqara_utils.MFG_CODE = MFG_CODE

local MOTION_ILLUMINANCE_ATTRIBUTE_ID = 0x0112
aqara_utils.MOTION_ILLUMINANCE_ATTRIBUTE_ID = MOTION_ILLUMINANCE_ATTRIBUTE_ID
local FREQUENCY_ATTRIBUTE_ID = 0x0102
aqara_utils.FREQUENCY_ATTRIBUTE_ID = FREQUENCY_ATTRIBUTE_ID
local SENSITIVITY_ATTRIBUTE_ID = 0x010C
aqara_utils.SENSITIVITY_ATTRIBUTE_ID = SENSITIVITY_ATTRIBUTE_ID

local MOTION_DETECTED_UINT32 = 65536
local MOTION_DETECTED_NUMBER = 1

local UNOCCUPIED_TIMER = "unoccupiedTimer"

local PREF_CHANGED_KEY = "prefChangedKey"
local PREF_CHANGED_VALUE = "prefChangedValue"

local PREF_FREQUENCY_KEY = "prefFrequency"
local PREF_FREQUENCY_VALUE_DEFAULT = 120
aqara_utils.PREF_FREQUENCY_VALUE_DEFAULT = PREF_FREQUENCY_VALUE_DEFAULT

local PREF_SENSITIVITY_KEY = "prefSensitivity"
local PREF_SENSITIVITY_VALUE_HIGH = 3
local PREF_SENSITIVITY_VALUE_MEDIUM = 2
local PREF_SENSITIVITY_VALUE_LOW = 1

local read_custom_attribute = function(device, cluster_id, attribute)
  local message = cluster_base.read_attribute(device, data_types.ClusterId(cluster_id), attribute)
  message.body.zcl_header.frame_ctrl:set_mfg_specific()
  message.body.zcl_header.mfg_code = data_types.validate_or_build_type(MFG_CODE, data_types.Uint16, "mfg_code")
  return message
end
aqara_utils.read_custom_attribute = read_custom_attribute

local write_motion_pref_attribute = function(device, cluster, attr, value)
  device:send(cluster_base.write_manufacturer_specific_attribute(device, cluster, attr, MFG_CODE,
    data_types.Uint8, value))
end
aqara_utils.write_motion_pref_attribute = write_motion_pref_attribute

local function motion_detected(driver, device, value, zb_rx)
  device:emit_event(capabilities.motionSensor.motion.active())

  local unoccupied_timer = device:get_field(UNOCCUPIED_TIMER)
  if unoccupied_timer then
    device.thread:cancel_timer(unoccupied_timer)
    device:set_field(UNOCCUPIED_TIMER, nil)
  end
  local detect_duration = device:get_field(PREF_FREQUENCY_KEY) or PREF_FREQUENCY_VALUE_DEFAULT
  print(detect_duration)
  local inactive_state = function()
    device:emit_event(capabilities.motionSensor.motion.inactive())
  end
  unoccupied_timer = device.thread:call_with_delay(detect_duration, inactive_state)
  device:set_field(UNOCCUPIED_TIMER, unoccupied_timer)
end

local function occupancy_attr_handler(driver, device, value, zb_rx)
  if value.value == MOTION_DETECTED_NUMBER then
    motion_detected(driver, device, value, zb_rx)
  end
end

aqara_utils.occupancy_attr_handler = occupancy_attr_handler

local function sensitivity_adjustment_handler(driver, device, command)
  local sensitivity = command.args.sensitivity
  if sensitivity == 'High' then
    device:set_field(PREF_CHANGED_KEY, PREF_SENSITIVITY_KEY)
    device:set_field(PREF_CHANGED_VALUE, PREF_SENSITIVITY_VALUE_HIGH)
    write_motion_pref_attribute(device, PRIVATE_CLUSTER_ID, SENSITIVITY_ATTRIBUTE_ID,
      PREF_SENSITIVITY_VALUE_HIGH)
  elseif sensitivity == 'Medium' then
    device:set_field(PREF_CHANGED_KEY, PREF_SENSITIVITY_KEY)
    device:set_field(PREF_CHANGED_VALUE, PREF_SENSITIVITY_VALUE_MEDIUM)
    write_motion_pref_attribute(device, PRIVATE_CLUSTER_ID, SENSITIVITY_ATTRIBUTE_ID,
      PREF_SENSITIVITY_VALUE_MEDIUM)
  elseif sensitivity == 'Low' then
    device:set_field(PREF_CHANGED_KEY, PREF_SENSITIVITY_KEY)
    device:set_field(PREF_CHANGED_VALUE, PREF_SENSITIVITY_VALUE_LOW)
    write_motion_pref_attribute(device, PRIVATE_CLUSTER_ID, SENSITIVITY_ATTRIBUTE_ID,
      PREF_SENSITIVITY_VALUE_LOW)
  end
end

aqara_utils.sensitivity_adjustment_handler = sensitivity_adjustment_handler

local function detection_frequency_handler(driver, device, command)
  local frequency = command.args.frequency
  device:set_field(PREF_CHANGED_KEY, PREF_FREQUENCY_KEY)
  device:set_field(PREF_CHANGED_VALUE, frequency)
  write_motion_pref_attribute(device, PRIVATE_CLUSTER_ID, FREQUENCY_ATTRIBUTE_ID, frequency)
end

aqara_utils.detection_frequency_handler = detection_frequency_handler

local function frequency_attr_handler(driver, device, value, zb_rx)
  local frequency = value.value
  device:set_field(PREF_FREQUENCY_KEY, frequency)
  device:emit_event(detectionFrequency.detectionFrequency(frequency))
end

aqara_utils.frequency_attr_handler = frequency_attr_handler

local function motion_illuminance_attr_handler(driver, device, value, zb_rx)
  -- The low 16 bits for Illuminance
  -- The high 16 bits for Motion Detection

  if value.value > MOTION_DETECTED_UINT32 then
    -- motion detected

    motion_detected(driver, device, value, zb_rx)

    local lux = value.value - MOTION_DETECTED_UINT32
    device:emit_event(capabilities.illuminanceMeasurement.illuminance(lux))
  end
end

aqara_utils.motion_illuminance_attr_handler = motion_illuminance_attr_handler

local function emit_sensitivity_event(device, sensitivity)
  if sensitivity == PREF_SENSITIVITY_VALUE_HIGH then
    device:emit_event(sensitivityAdjustment.sensitivityAdjustment.High())
  elseif sensitivity == PREF_SENSITIVITY_VALUE_MEDIUM then
    device:emit_event(sensitivityAdjustment.sensitivityAdjustment.Medium())
  elseif sensitivity == PREF_SENSITIVITY_VALUE_LOW then
    device:emit_event(sensitivityAdjustment.sensitivityAdjustment.Low())
  end
end

local function sensitivity_attr_handler(driver, device, value, zb_rx)
  local sensitivity = value.value
  emit_sensitivity_event(device, sensitivity)
end

aqara_utils.sensitivity_attr_handler = sensitivity_attr_handler

local function write_attr_res_handler(driver, device, zb_rx)
  -- write attribute response for prefs
  local key = device:get_field(PREF_CHANGED_KEY) or ''
  local value = device:get_field(PREF_CHANGED_VALUE) or 0
  if key == PREF_FREQUENCY_KEY then
    -- for unoccupied timer
    device:set_field(PREF_FREQUENCY_KEY, value)
    -- update ui
    device:emit_event(detectionFrequency.detectionFrequency(value))
  elseif key == PREF_SENSITIVITY_KEY then
    emit_sensitivity_event(device, value)
  end
end

aqara_utils.write_attr_res_handler = write_attr_res_handler

return aqara_utils
