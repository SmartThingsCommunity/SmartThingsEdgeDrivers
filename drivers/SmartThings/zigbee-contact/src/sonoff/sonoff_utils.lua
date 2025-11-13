--[[
Description: 
Version: 2.0
Autor: liangjia
Date: 2024-01-24 12:00:32
LastEditors: liangjia
LastEditTime: 2024-02-02 15:20:58
--]]
--[[
Description: 
Version: 2.0
Autor: liangjia
Date: 2024-01-19 18:05:31
LastEditors: liangjia
LastEditTime: 2024-01-20 13:51:20
--]]
--[[
Description: 
Version: 2.0
Autor: liangjia
Date: 2024-01-19 15:39:47
LastEditors: liangjia
LastEditTime: 2024-01-19 16:18:46
--]]
local capabilities = require "st.capabilities"
local log = require "log"
local zb_const = require "st.zigbee.constants"

local OCCUPANCY_CLUSTER_ID = 0x0406
local OCCUPANCY_UTO_ATTRIBUTE_ID = 0x0020
local MFG_CODE = 0x1286
local SONOFF_PRIVITE_CLUSTER_ID = 0xFC11
local SONOFF_ILLUMINATION_LEVEL_ATTRIBUTE_ID = 0x2001
local SONOFF_SPILT_ATTRIBUTE_ID = 0x2000

local sonoff_utils = {}

local PREF_FREQUENCY_KEY = "prefFrequency"
local PREF_FREQUENCY_VALUE_DEFAULT = 60


local PREF_SENSITIVITY_KEY = "sensitivity"
local PREF_SENSITIVITY_VALUE_DEFAULT = 2

local PREF_CHANGED_KEY = "prefChangedKey"
local PREF_CHANGED_VALUE = "prefChangedValue"

local function motion_detected(device)
  device:emit_event(capabilities.motionSensor.motion.active())
end

local function get_pref_changed_field(device)
  local key = device:get_field(PREF_CHANGED_KEY) or ''
  local value = device:get_field(PREF_CHANGED_VALUE) or 0
  return key, value
end

local function set_pref_changed_field(device, key, value)
  log.debug("set_pref_changed_field---->value:",value)
  device:set_field(PREF_CHANGED_KEY, key)
  device:set_field(PREF_CHANGED_VALUE, value)
end

sonoff_utils.OCCUPANCY_CLUSTER_ID = OCCUPANCY_CLUSTER_ID
sonoff_utils.OCCUPANCY_UTO_ATTRIBUTE_ID = OCCUPANCY_UTO_ATTRIBUTE_ID
sonoff_utils.MFG_CODE = MFG_CODE

sonoff_utils.PREF_FREQUENCY_KEY = PREF_FREQUENCY_KEY
sonoff_utils.PREF_FREQUENCY_VALUE_DEFAULT = PREF_FREQUENCY_VALUE_DEFAULT
sonoff_utils.PREF_SENSITIVITY_KEY = PREF_SENSITIVITY_KEY
sonoff_utils.PREF_SENSITIVITY_VALUE_DEFAULT = PREF_SENSITIVITY_VALUE_DEFAULT
sonoff_utils.SONOFF_PRIVITE_CLUSTER_ID = SONOFF_PRIVITE_CLUSTER_ID
sonoff_utils.SONOFF_ILLUMINATION_LEVEL_ATTRIBUTE_ID = SONOFF_ILLUMINATION_LEVEL_ATTRIBUTE_ID
sonoff_utils.SONOFF_SPILT_ATTRIBUTE_ID = SONOFF_SPILT_ATTRIBUTE_ID
sonoff_utils.motion_detected = motion_detected
sonoff_utils.get_pref_changed_field = get_pref_changed_field
sonoff_utils.set_pref_changed_field = set_pref_changed_field

return sonoff_utils
