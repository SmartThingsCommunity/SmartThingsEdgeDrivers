local log = require "log"
local st_utils = require "st.utils"

local api = require "api.apis"
local const = require "constants"

local Devices = {}

local supported_devices = {"L75ms", "L42ms", "MA510", "MA710", "MA7100HP", "MA9100HP"}
local MNID = "0BE8"
local SetupID = {
  L75ms = "602",
  L42ms = "603",
  MA510 = "604",
  MA710 = "605",
  MA7100HP = "606",
  MA9100HP = "607",
}

local devices_model_info = {
  [SetupID.L75ms] = {
    profile = "l42ms",
    manufacturer = "JBL",
    model = "L75ms",
  },
  [SetupID.L42ms] = {
    profile = "l42ms",
    manufacturer = "JBL",
    model = "L42ms",
  },
  [SetupID.MA510] = {
    profile = "maX10",
    manufacturer = "JBL",
    model = "MA510",
  },
  [SetupID.MA710] = {
    profile = "maX10",
    manufacturer = "JBL",
    model = "MA710",
  },
  [SetupID.MA7100HP] = {
    profile = "maX10",
    manufacturer = "JBL",
    model = "MA7100HP",
  },
  [SetupID.MA9100HP] = {
    profile = "maX10",
    manufacturer = "JBL",
    model = "MA9100HP",
  },
}

function Devices.GetSupportedDevices()
  log.info(string.format("GetSupportedDevices: supported models: %s"), st_utils.stringify_table(supported_devices))
  return supported_devices
end

local function GetDefaultDeviceInfo(dni, ip)
  local label, manufacturer, model, vendor, err
  label, err = api.GetDeviceName(ip)
  if err or type(label) ~= "string" then
    log.warn(string.format("Failed to get Device Name from device with IP: %s", ip))
    label = const.DEFAULT_DEVICE_NAME
  end
  manufacturer, err = api.GetManufacturerName(ip)
  if err or type(manufacturer) ~= "string" then
    log.warn(string.format("Failed to get Manufacturer Name from device with IP: %s", ip))
    manufacturer = const.DEFAULT_MANUFACTURER_NAME
  end
  model, err = api.GetModelName(ip)
  if err or type(model) ~= "string" then
    log.warn(string.format("Failed to get Device Name from device with IP: %s", ip))
    model = const.DEFAULT_MODEL_NAME
  end
  vendor, err = api.GetProductName(ip)
  if err or type(vendor) ~= "string" then
    log.warn(string.format("Failed to get Product Name from device with IP: %s", ip))
    vendor = const.DEFAULT_PRODUCT_NAME
  end

  local device_info = {
    type = "LAN",
    device_network_id = dni,
    label = label,
    profile = "harman-luxury",
    manufacturer = manufacturer,
    model = model,
    vendor_provided_label = vendor,
  }

  return device_info
end

function Devices.get_device_info(dni, params)
  if params.mnid == MNID then
    if devices_model_info[params.setupid] ~= nil then
      local label, err = api.GetDeviceName(params.ip)
      if err or type(label) ~= "string" then
        log.warn(string.format("Failed to get Device Name from device with IP: %s", params.ip))
        label = const.DEFAULT_DEVICE_NAME
      end
      local model_info = devices_model_info[params.setupid]
      local device_info = {
        type = "LAN",
        device_network_id = dni,
        label = label,
        profile = model_info.profile,
        manufacturer = model_info.manufacturer,
        model = model_info.model,
        vendor_provided_label = label,
      }
      return device_info
    end
  end

  -- if device lacks or have the wrong MNID or unsupported SetupID, grub info from device
  log.warn(string.format(
             "Devices.get_device_info: Failed to get supported MNID or SetupID, using info from device with IP:",
             params.ip))
  return GetDefaultDeviceInfo(dni, params.ip)
end

return Devices
