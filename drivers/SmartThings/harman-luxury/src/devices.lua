local log = require "log"
local st_utils = require "st.utils"

local api = require "api.apis"

Devices = {}

local suppourted_devices = { "L75ms", "L42ms", "AVR5" }

local MNID = "0BE8"
local DEFAULT_DEVICE_NAME = "HarmanLuxury"
local DEFAULT_MANUFACTURE_NAME = "Harman Luxury Audio"
local DEFAULT_MODEL_NAME = "Harman Luxury"
local DEFAULT_PRODUCT_NAME = "Harman Luxury"

local devices_SetupID = {
    L75ms = "602",
    L42ms = "603",
    AVR5 = "604"
}

function Devices.GetSupportedDevices()
    log.info("GetSupportedDevices: supported models: " .. st_utils.stringify_table(suppourted_devices))
    return suppourted_devices
end

local function GetDefaultDeviceInfo(dni, ip)
    local label = api.GetDeviceName(ip)
    if not label then
        log.warn("Failed to get Device Name from device with IP:" .. ip)
        label = DEFAULT_DEVICE_NAME
    end
    local manufacturer = api.GetManufatureName(ip)
    if not manufacturer then
        log.warn("Failed to get Manufacture Name from device with IP:" .. ip)
        manufacturer = DEFAULT_MANUFACTURE_NAME
    end
    local model = api.GetModelName(ip)
    if not model then
        log.warn("Failed to get Device Name from device with IP:" .. ip)
        model = DEFAULT_MODEL_NAME
    end
    local vendor = api.GetProductName(ip)
    if not vendor then
        log.warn("Failed to get Product Name from device with IP:" .. ip)
        vendor = DEFAULT_PRODUCT_NAME
    end

    local device_info = {
        type = "LAN",
        device_network_id = dni,
        label = label,
        profile = "harman-luxury",
        manufacturer = manufacturer,
        model = model,
        vendor_provided_label = vendor
    }

    return device_info
end

local function GetL75msDeviceInfo(dni, ip)
    local label = api.GetDeviceName(ip)
    if not label then
        log.warn("Failed to get Device Name from device with IP:" .. ip)
        label = DEFAULT_DEVICE_NAME
    end

    local device_info = {
        type = "LAN",
        device_network_id = dni,
        label = label,
        profile = "harman-luxury",
        manufacturer = "JBL",
        model = "L75ms",
        vendor_provided_label = label
    }

    return device_info
end

local function GetL42msDeviceInfo(dni, ip)
    local label = api.GetDeviceName(ip)
    if not label then
        log.warn("Failed to get Device Name from device with IP:" .. ip)
        label = DEFAULT_DEVICE_NAME
    end

    local device_info = {
        type = "LAN",
        device_network_id = dni,
        label = label,
        profile = "harman-luxury",
        manufacturer = "JBL",
        model = "L42ms",
        vendor_provided_label = label
    }

    return device_info
end

local function GetAvr5DeviceInfo(dni, ip)
    local label = api.GetDeviceName(ip)
    if not label then
        log.warn("Failed to get Device Name from device with IP:" .. ip)
        label = DEFAULT_DEVICE_NAME
    end

    local device_info = {
        type = "LAN",
        device_network_id = dni,
        label = label,
        profile = "harman-luxury",
        manufacturer = "ARCAM",
        model = "AVR5",
        vendor_provided_label = label
    }

    return device_info
end

function Devices.get_device_info(dni, params)
    if params.mnid == MNID then
        if devices_SetupID["L75ms"] == params.setupid then
            log.info("Devices.get_device_info: get device info for L75ms from device with IP:" .. params.ip)
            return GetL75msDeviceInfo(dni, params.ip)
        elseif devices_SetupID["L42ms"] == params.setupid then
            log.info("Devices.get_device_info: get device info for L42ms from device with IP:" .. params.ip)
            return GetL42msDeviceInfo(dni, params.ip)
        elseif devices_SetupID["AVR5"] == params.setupid then
            log.info("Devices.get_device_info: get device info for AVR5 from device with IP:" .. params.ip)
            return GetAvr5DeviceInfo(dni, params.ip)
        end
    end

    -- if device lacks or have the wrong MNID or unsupported SetupID, grub info from device
    log.warn("Devices.get_device_info: Failed to get supported MNID or SetupID, using info from device with IP:" ..
    params.ip)
    return GetDefaultDeviceInfo(dni, params.ip)
end

return Devices
