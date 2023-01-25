local zcl_clusters = require "st.zigbee.zcl.clusters"
local Level = zcl_clusters.Level
local OnOff = zcl_clusters.OnOff
local Groups = zcl_clusters.Groups
local PowerConfiguration = zcl_clusters.PowerConfiguration

local capabilities = require "st.capabilities"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"


local WIRELESS_REMOTE_FINGERPRINTS = {
  { mfr = "ROBB smarrt", model = "ROB_200-007-0" }
}

local function can_handle(opts, driver, device, ...)
  for _, fingerprint in ipairs(WIRELESS_REMOTE_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function component_to_endpoint(device, component_id)
  local ep_num = component_id:match("switch(%d)")
  return ep_num and tonumber(ep_num) or device.fingerprinted_endpoint_id
end

local function endpoint_to_component(device, ep)
  local switch_comp = string.format("switch%d", ep)
  if device.profile.components[switch_comp] ~= nil then
    return switch_comp
  else
    return "main"
  end
end

local device_init = function(self, device)
  device:set_component_to_endpoint_fn(component_to_endpoint)
  device:set_endpoint_to_component_fn(endpoint_to_component)

  battery_defaults.build_linear_voltage_init(2.1, 3.0)
end

local robb_wireless_8_control = {
  NAME = "ROBB Wireless 8 Remote Control",
  supported_capabilities = {
    capabilities.battery,
    capabilities.switch,
  },
  lifecycle_handlers = {
    init = device_init,
    -- init = battery_defaults.build_linear_voltage_init(2.1, 3.0),
    -- added = added_handler,
    -- doConfigure = do_configuration
  },
  can_handle = can_handle
}

return robb_wireless_8_control
