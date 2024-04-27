---@enum HueDeviceTypes
local HueDeviceTypes = {
  BRIDGE = "bridge",
  BUTTON = "button",
  CONTACT = "contact",
  DEVICE_POWER = "device_power",
  LIGHT = "light",
  LIGHT_LEVEL = "light_level",
  MOTION = "motion",
  TAMPER = "tamper",
  TEMPERATURE = "temperature",
  ZIGBEE_CONNECTIVITY = "zigbee_connectivity"
}

local SupportedNumberOfButtons = {
  [1] = true, -- For Philips Hue Smart Button device which contains only 1 button
  [4] = true, -- For Philips Hue Dimmer Remote which contains 4 buttons
}

local PrimaryDeviceTypes = {
  [HueDeviceTypes.BUTTON] = true,
  [HueDeviceTypes.CONTACT] = true,
  [HueDeviceTypes.LIGHT] = true,
  [HueDeviceTypes.MOTION] = true
}

---@type table<string,HueDeviceTypes>
local bimap = {}

for key, val in pairs(HueDeviceTypes) do
  bimap[val] = key
end

function HueDeviceTypes.can_join_device_for_service(device_type_str)
  return PrimaryDeviceTypes[device_type_str]
end

function HueDeviceTypes.is_valid_device_type(device_type_str)
  return bimap[device_type_str] ~= nil
end

function HueDeviceTypes.supports_button_configuration(button_description)
  return SupportedNumberOfButtons[button_description.num_buttons]
end

return HueDeviceTypes
