--[[
Description: 
Version: 2.0
Autor: liangjia
Date: 2024-04-25 13:38:25
LastEditors: liangjia
LastEditTime: 2024-04-25 13:53:04
--]]
--[[
Description: 
Version: 2.0
Autor: liangjia
Date: 2024-04-25 13:38:25
LastEditors: liangjia
LastEditTime: 2024-04-25 13:47:42
--]]
--[[
Description: 
Version: 2.0
Autor: liangjia
Date: 2024-01-19 18:05:31
LastEditors: liangjia
LastEditTime: 2024-01-20 10:41:41
--]]
local capabilities = require "st.capabilities"
local zcl_commands = require "st.zigbee.zcl.global_commands"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local sonoff_utils = require "sonoff/sonoff_utils"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local zb_const = require "st.zigbee.constants"
local write_attr_response = require "st.zigbee.zcl.global_commands.write_attribute_response"
local data_types = require "st.zigbee.data_types"
local Status = (require "st.zigbee.zcl.types").ZclStatus
local log = require "log"

local PREF_TEMPERATRUE_UNIT_VALUE_CELSIUS = 0
local PREF_TEMPERATRUE_UNIT_VALUE_FAHRENHEIT = 1


local capability_screenTemperatureDisplayUnit = capabilities["samplereturn62595.screenTemperatureDisplayUnit"]
local command_setScreenTemperatureDisplayUnit = "setScreenTemperatureDisplayUnit"

local capability_temperatureCompensation = capabilities["samplereturn62595.temperatureCompensation"]
local command_setTemperatureCompensation = "setTemperatureCompensation"

local capability_humidityCompensation = capabilities["samplereturn62595.humidityCompensation"]
local command_setHumidityCompensation = "setHumidityCompensation"

local FINGERPRINTS = {
    { mfr = "SONOFF", model = "SNZB-02LD" },
    { mfr = "SONOFF", model = "SNZB-02WD" }
}





local function added_handler(self, device)
    --update UI 
    log.debug("TH sensor added_handler >>>>>>")
    device:emit_event(capability_screenTemperatureDisplayUnit.screenTemperatureDisplayUnit.Celsius())
    device:emit_event(capability_temperatureCompensation.temperatureCompensation(sonoff_utils.PREF_TEMPERATURE_COMPENSATION_VALUE_DEFAULT))
    device:emit_event(capability_humidityCompensation.humidityCompensation(sonoff_utils.PREF_HUMIDITY_COMPENSATION_VALUE_DEFAULT))
    log.debug("TH sensor added_handler end!")
end


local function device_init(driver, device)
    --do notthing
end


local function send_screen_temperature_display_unit_value(device, value)
    -- Store key
    sonoff_utils.set_pref_changed_field(device, sonoff_utils.PREF_TEMPERATRUE_UNIT_KEY, value)
    log.debug("---->send_screen_temperature_display_unit_value:", sonoff_utils.ZCL_TEMPERATRUE_UNIT_ATTRIBUTE_ID)
    -- Write Attribute 
    device:send(sonoff_utils.custom_write_attribute(device,
        sonoff_utils.ZCL_SONOFF_PRIVITE_CLUSTER_ID,
        sonoff_utils.ZCL_TEMPERATRUE_UNIT_ATTRIBUTE_ID,
        nil,
        data_types.Uint16,
        value))
end


local function send_temperature_compensation_value(device, value)
    -- Store key
    sonoff_utils.set_pref_changed_field(device, sonoff_utils.PREF_TEMPERATURE_COMPENSATION_KEY, value)
    log.debug("---->send_temperature_compensation_value:", sonoff_utils.ZCL_TEMPERATURE_COMPENSATION_ATTRIBUTE_ID)
    -- Write Attribute 
    device:send(sonoff_utils.custom_write_attribute(device,
        sonoff_utils.ZCL_SONOFF_PRIVITE_CLUSTER_ID,
        sonoff_utils.ZCL_TEMPERATURE_COMPENSATION_ATTRIBUTE_ID,
        nil,
        data_types.Int16,
        value * 100))
end


local function send_humidity_compensation_value(device, value)
    -- Store key
    sonoff_utils.set_pref_changed_field(device, sonoff_utils.PREF_HUMIDITY_COMPENSATION_KEY, value)
    log.debug("---->send_humidity_compensation_value:", sonoff_utils.ZCL_HUMIDITY_COMPENSATION_ATTRIBUTE_ID)
    -- Write Attribute 
    device:send(sonoff_utils.custom_write_attribute(device,
        sonoff_utils.ZCL_SONOFF_PRIVITE_CLUSTER_ID,
        sonoff_utils.ZCL_HUMIDITY_COMPENSATION_ATTRIBUTE_ID,
        nil,
        data_types.Int16,
        value * 100))
end


local function screen_temperature_display_unit_capability_handler(driver, device, command)
    log.debug("screen_temperature_display_unit_capability_handler enter")
    local display_unit = command.args.screenTemperatureDisplayUnit
    log.debug("---->screen temperature display unit:", display_unit)
    -- Store key
    -- Update UI
    if display_unit == 'Celsius' then
        send_screen_temperature_display_unit_value(device, PREF_TEMPERATRUE_UNIT_VALUE_CELSIUS)
    elseif display_unit == 'Fahrenheit' then
        send_screen_temperature_display_unit_value(device, PREF_TEMPERATRUE_UNIT_VALUE_FAHRENHEIT)
    end
end


local function temperature_compensation_capability_handler(driver, device, command)
    log.debug("temperature_compensation_capability_handler enter")
    local temp_compensation = command.args.temperatureCompensation
    log.debug("---->temperature compensation:", temp_compensation)
    -- Store key
    -- Update UI
    send_temperature_compensation_value(device, temp_compensation)
end


local function humidity_compensation_capability_handler(driver, device, command)
    log.debug("humidity_compensation_capability_handler enter")
    local humidity_compensation = command.args.humidityCompensation
    log.debug("---->humidity compensation:", humidity_compensation)
    -- Store key
    -- Update UI
    send_humidity_compensation_value(device, humidity_compensation)
end


local function screen_temperature_display_unit_attr_handler(driver, device, value, zb_rx)
    log.debug("---->ZB Rx screen temperature display unit Value", value.value)
    local raw_value = value.value
    if raw_value == PREF_TEMPERATRUE_UNIT_VALUE_CELSIUS then
        device:emit_event(capability_screenTemperatureDisplayUnit.screenTemperatureDisplayUnit.Celsius())
    elseif raw_value == PREF_TEMPERATRUE_UNIT_VALUE_FAHRENHEIT then
        device:emit_event(capability_screenTemperatureDisplayUnit.screenTemperatureDisplayUnit.Fahrenheit())
    end
end


local function write_attr_response_handler(driver, device, zb_rx)
    log.debug("write_attr_response_handler enter")
    --judge write resp success ?
    log.debug("debug", write_attr_response.WriteAttributeResponse.ID)
    log.debug(string.format("received Zigbee message: %s", zb_rx:pretty_print()))
    log.debug(string.format("received Zigbee message: %s", zb_rx.body.zcl_body:pretty_print()))
    log.debug("received Zigbee message:", zb_rx.body.zcl_body.global_status.value)

    local war = zb_rx.body.zcl_body
    if war.global_status ~= nil and war.global_status.value == Status.SUCCESS then
        log.debug("Write was successful")
        local key, value = sonoff_utils.get_pref_changed_field(device)
        if key == sonoff_utils.PREF_TEMPERATRUE_UNIT_KEY then
            -- Reset key
            sonoff_utils.set_pref_changed_field(device, '', 0)
            -- Update UI
            log.debug("screenTemperatureDisplayUnit:", value)
            if value == PREF_TEMPERATRUE_UNIT_VALUE_CELSIUS then
                device:emit_event(capability_screenTemperatureDisplayUnit.screenTemperatureDisplayUnit.Celsius())
            elseif value == PREF_TEMPERATRUE_UNIT_VALUE_FAHRENHEIT then
                device:emit_event(capability_screenTemperatureDisplayUnit.screenTemperatureDisplayUnit.Fahrenheit())
            end
        end

        if key == sonoff_utils.PREF_TEMPERATURE_COMPENSATION_KEY then
            local real_tc_value = value
            -- reset key
            sonoff_utils.set_pref_changed_field(device, '', 0)
            -- update ui
            log.debug("temperature compensation:", real_tc_value)
            device:emit_event(capability_temperatureCompensation.temperatureCompensation(real_tc_value))
        end

        if key == sonoff_utils.PREF_HUMIDITY_COMPENSATION_KEY then
            local real_hc_value = value
            -- reset key
            sonoff_utils.set_pref_changed_field(device, '', 0)
            -- update ui
            log.debug("humidity compensation:", real_hc_value)
            device:emit_event(capability_humidityCompensation.humidityCompensation(real_hc_value))
        end
    end
end



local is_sonoff_products = function(opts, driver, device)
    for _, fingerprint in ipairs(FINGERPRINTS) do
        if device:get_model() == fingerprint.model then
            return true
        end
    end
    return false
end


local sonoff_temp_humidity_sensor_handler = {
    NAME = "Sonoff temperature and humidity sensor Handler",
    lifecycle_handlers = {
        init = device_init,
        added = added_handler
    },
    -- 能力点处理程序
    capability_handlers = {
        [capability_screenTemperatureDisplayUnit.ID] = {
            [command_setScreenTemperatureDisplayUnit] = screen_temperature_display_unit_capability_handler
        },
        [capability_temperatureCompensation.ID] = {
            [command_setTemperatureCompensation] = temperature_compensation_capability_handler
        },
        [capability_humidityCompensation.ID] = {
            [command_setHumidityCompensation] = humidity_compensation_capability_handler
        }
    },
    zigbee_handlers = {
        -- 属性处理
        attr = {
            [sonoff_utils.ZCL_SONOFF_PRIVITE_CLUSTER_ID] = {
                [sonoff_utils.ZCL_TEMPERATRUE_UNIT_ATTRIBUTE_ID] = screen_temperature_display_unit_attr_handler
            }
        },
        -- 全局处理
        global = {
            [sonoff_utils.ZCL_SONOFF_PRIVITE_CLUSTER_ID] = {
                [zcl_commands.WriteAttributeResponse.ID] = write_attr_response_handler
            }
        }
    },
    sub_drivers = {
        require("sonoff/SNZB-02LD")
    },
    can_handle = is_sonoff_products
}

return sonoff_temp_humidity_sensor_handler
