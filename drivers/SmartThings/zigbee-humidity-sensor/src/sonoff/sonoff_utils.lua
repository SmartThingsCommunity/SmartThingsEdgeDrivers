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
local zb_const = require "st.zigbee.constants"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local log = require "log"

-- Zigbee Manufacturer Code
local MFG_CODE_NULL = 0x0000
local MFG_CODE_EWELINK = 0x1286

-- Zigbee cluster IDs -- sonoff private cluster
local ZCL_SONOFF_PRIVITE_CLUSTER_ID = 0xFC11
-- Zigbee attribute IDs
local ZCL_TEMPERATRUE_UNIT_ATTRIBUTE_ID = 0x0007
local ZCL_TEMPERATURE_COMPENSATION_ATTRIBUTE_ID = 0x2003
local ZCL_HUMIDITY_COMPENSATION_ATTRIBUTE_ID= 0x2004

local PREF_CHANGED_KEY = "prefChangedKey"
local PREF_CHANGED_VALUE = "prefChangedValue"

local PREF_TEMPERATRUE_UNIT_KEY = "screenTemperatureDisplayUnit"
local PREF_TEMPERATRUE_UNIT_VALUE_DEFAULT = 0

local PREF_TEMPERATURE_COMPENSATION_KEY = "temperatureCompensation"
local PREF_TEMPERATURE_COMPENSATION_VALUE_DEFAULT = 0.0

local PREF_HUMIDITY_COMPENSATION_KEY = "humidityCompensation"
local PREF_HUMIDITY_COMPENSATION_VALUE_DEFAULT = 0.0


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

local custom_read_attribute = function(device, cluster, attribute, mfg_code)
    local message = cluster_base.read_attribute(device, data_types.ClusterId(cluster), attribute)
    if mfg_code ~= nil then
        message.body.zcl_header.frame_ctrl:set_mfg_specific()
        message.body.zcl_header.mfg_code = data_types.validate_or_build_type(mfg_code, data_types.Uint16, "mfg_code")
    end
    return message
end

local function custom_sign(number)
    if _VERSION and _VERSION:match("^5%.3") then
        -- Lua 5.3及以上版本，直接使用math.sign
        return math.sign(number)
    else
        -- Lua 5.2及以下版本，实现一个替代的sign函数
        if number > 0 then
            return 1
        elseif number < 0 then
            return -1
        else
            -- 处理数字为零的情况
            return 0
        end
    end
end

local custom_write_attribute = function(device, cluster, attribute, mfg_code, data_type, value)
    local sign = custom_sign(value) -- 获取数字的符号（正1或负-1）
    local abs_number = math.abs(value) -- 获取数字的绝对值
    local integer_part = math.floor(abs_number) -- 对绝对值进行向下取整
    local real_value =sign * integer_part -- 根据原始数字的符号恢复截断后的整数

    log.debug("---->custom_write_attribute real_value:", real_value)

    local data = data_types.validate_or_build_type(real_value, data_type)
    local message = cluster_base.write_attribute(device, data_types.ClusterId(cluster), attribute, data)
    if mfg_code ~= nil then
        message.body.zcl_header.frame_ctrl:set_mfg_specific()
        message.body.zcl_header.mfg_code = data_types.validate_or_build_type(mfg_code, data_types.Uint16, "mfg_code")
    end
    return message
end

local sonoff_utils = {}

sonoff_utils.PREF_TEMPERATRUE_UNIT_KEY = PREF_TEMPERATRUE_UNIT_KEY
sonoff_utils.PREF_TEMPERATRUE_UNIT_VALUE_DEFAULT = PREF_TEMPERATRUE_UNIT_VALUE_DEFAULT

sonoff_utils.PREF_TEMPERATURE_COMPENSATION_KEY = PREF_TEMPERATURE_COMPENSATION_KEY
sonoff_utils.PREF_TEMPERATURE_COMPENSATION_VALUE_DEFAULT = PREF_TEMPERATURE_COMPENSATION_VALUE_DEFAULT

sonoff_utils.PREF_HUMIDITY_COMPENSATION_KEY = PREF_HUMIDITY_COMPENSATION_KEY
sonoff_utils.PREF_HUMIDITY_COMPENSATION_VALUE_DEFAULT = PREF_HUMIDITY_COMPENSATION_VALUE_DEFAULT

sonoff_utils.MFG_CODE_NULL = MFG_CODE_NULL
sonoff_utils.MFG_CODE_EWELINK = MFG_CODE_EWELINK

sonoff_utils.ZCL_SONOFF_PRIVITE_CLUSTER_ID = ZCL_SONOFF_PRIVITE_CLUSTER_ID
sonoff_utils.ZCL_TEMPERATRUE_UNIT_ATTRIBUTE_ID = ZCL_TEMPERATRUE_UNIT_ATTRIBUTE_ID
sonoff_utils.ZCL_TEMPERATURE_COMPENSATION_ATTRIBUTE_ID = ZCL_TEMPERATURE_COMPENSATION_ATTRIBUTE_ID
sonoff_utils.ZCL_HUMIDITY_COMPENSATION_ATTRIBUTE_ID = ZCL_HUMIDITY_COMPENSATION_ATTRIBUTE_ID

sonoff_utils.get_pref_changed_field = get_pref_changed_field
sonoff_utils.set_pref_changed_field = set_pref_changed_field

sonoff_utils.custom_read_attribute = custom_read_attribute
sonoff_utils.custom_write_attribute = custom_write_attribute

return sonoff_utils
