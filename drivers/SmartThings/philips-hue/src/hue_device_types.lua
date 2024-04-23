local HueDeviceTypes = {
  BRIDGE = "bridge",
  LIGHT = "light"
}

local bimap = {}

for key, val in pairs(HueDeviceTypes) do
  bimap[val] = key
end

function HueDeviceTypes.is_valid_device_type(device_type_str)
  return bimap[device_type_str] ~= nil
end

return HueDeviceTypes
