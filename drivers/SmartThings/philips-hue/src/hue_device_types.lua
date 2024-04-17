---@enum HueDeviceTypes
local HueDeviceTypes = {
  BRIDGE = "bridge",
  CONTACT = "contact",
  DEVICE_POWER = "device_power",
  LIGHT = "light",
  LIGHT_LEVEL = "light_level",
  MOTION = "motion",
  TAMPER = "tamper",
  TEMPERATURE = "temperature",
  ZIGBEE_CONNECTIVITY = "zigbee_connectivity"
}

local PrimaryDeviceTypes = {
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

return HueDeviceTypes
