local capabilities = require "st.capabilities"

local aqara_utils = {}

local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID = 0x0009
local MFG_CODE = 0x115F

local UNOCCUPIED_TIMER = "unoccupiedTimer"

local PREF_FREQUENCY_KEY = "prefFrequency"
local PREF_FREQUENCY_VALUE_DEFAULT = 60

local PREF_CHANGED_KEY = "prefChangedKey"
local PREF_CHANGED_VALUE = "prefChangedValue"

local function motion_detected(device)
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

aqara_utils.PRIVATE_CLUSTER_ID = PRIVATE_CLUSTER_ID
aqara_utils.PRIVATE_ATTRIBUTE_ID = PRIVATE_ATTRIBUTE_ID
aqara_utils.MFG_CODE = MFG_CODE
aqara_utils.PREF_FREQUENCY_KEY = PREF_FREQUENCY_KEY
aqara_utils.PREF_FREQUENCY_VALUE_DEFAULT = PREF_FREQUENCY_VALUE_DEFAULT
aqara_utils.motion_detected = motion_detected
aqara_utils.get_pref_changed_field = get_pref_changed_field
aqara_utils.set_pref_changed_field = set_pref_changed_field

return aqara_utils
