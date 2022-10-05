local capabilities = require "st.capabilities"
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"
local device_lib = require "st.device"

local function added(driver, device, event)
  if device.network_type == device_lib.NETWORK_TYPE_ZIGBEE then
    for i = 1,2 do
      local name = string.format("%s outlet %d", device.label, i)
      local metadata = {
        type = "EDGE_CHILD",
        label = name,
        profile = "switch-power-parent-child",
        parent_device_id = device.id,
        parent_assigned_child_key = string.format("%02X", i),
        vendor_provided_label = name,
      }
      driver:try_create_device(metadata)
    end
  end
end

local function find_child(parent, ep_id)
  return parent:get_child_by_parent_assigned_key(string.format("%02X", ep_id))
end

local function init(driver, device, event)
  if device.network_type == device_lib.NETWORK_TYPE_ZIGBEE then
    device:set_find_child(find_child)
  end
end

local zigbee_dual_metering_switch = {
  supported_capabilities = {
    capabilities.switch,
    capabilities.powerMeter
  },
  lifecycle_handlers = {
    added = added,
    init =  init,
  }
}

defaults.register_for_default_handlers(zigbee_dual_metering_switch, zigbee_dual_metering_switch.supported_capabilities)
local zigbee_light_switch = ZigbeeDriver("Zigbee Dual Metering Switch", zigbee_dual_metering_switch)
zigbee_light_switch:run()