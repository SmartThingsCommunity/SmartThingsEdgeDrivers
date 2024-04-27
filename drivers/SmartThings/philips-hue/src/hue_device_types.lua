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
  [1] = true, -- For Philips Hue Smart Button or single switch In-Wall Switch module which contains only 1 button
  [2] = true, -- For double switch In-Wall Switch module
  [4] = true, -- For Philips Hue Dimmer Remote and Tap Dial, which contains 4 buttons
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

---@param device_info HueDeviceInfo
---@param primary_services table<HueDeviceTypes,HueServiceInfo[]>
---@return HueDeviceTypes? svc_rtype the main service rtype for the device
function HueDeviceTypes.determine_main_service_rtype(device_info, primary_services)
  -- If the id_v1 is present, it'll be of the form '/<service>/<number>'
  local service_from_v1_id = string.match((device_info.id_v1 or ""), "/([%a]+)/[%d]+") or ""
  -- Lights show up as `light` here, but buttons and sensors both show up as `sensors`
  if PrimaryDeviceTypes[service_from_v1_id] then
    return service_from_v1_id
  end

  local has_service = {}
  for rtype, _ in pairs(primary_services) do
    has_service[rtype] = PrimaryDeviceTypes[rtype]
  end

  -- At this point we'll make our best guess by establishing an order of precedence as a heuristic;
  -- lights first, then the actual sensors, then buttons.
  if has_service[HueDeviceTypes.LIGHT] then return HueDeviceTypes.LIGHT end
  if has_service[HueDeviceTypes.CONTACT] then return HueDeviceTypes.CONTACT end
  if has_service[HueDeviceTypes.MOTION] then return HueDeviceTypes.MOTION end
  if has_service[HueDeviceTypes.BUTTON] then return HueDeviceTypes.BUTTON end

  return nil
end

return HueDeviceTypes
