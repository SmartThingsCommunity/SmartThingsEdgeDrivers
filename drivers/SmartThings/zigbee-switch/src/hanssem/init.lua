local stDevice = require "st.device"
local capabilities = require "st.capabilities"
local zclClusters = require "st.zigbee.zcl.clusters"
local zclGlobalCommands = require "st.zigbee.zcl.global_commands"
local Status = require "st.zigbee.generated.types.ZclStatus"
local OnOff = zclClusters.OnOff

local FINGERPRINTS = {
  { mfr = "Winners", model = "HS2-P1Z3-1", children = 0 },
  { mfr = "Winners", model = "HS2-P1Z3-2", children = 1 },
  { mfr = "Winners", model = "HS2-P1Z3-3", children = 2 },
  { mfr = "Winners", model = "HS2-P2Z3-4", children = 3 },
  { mfr = "Winners", model = "HS2-P2Z3-5", children = 4 },
  { mfr = "Winners", model = "HS2-P2Z3-6", children = 5 }
}

local function can_handle_hanssem_switch(opts, driver, device, ...)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function get_children_amount(device)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_model() == fingerprint.model then
      return fingerprint.children
    end
  end
end

local function find_child(parent, ep_id)
  return parent:get_child_by_parent_assigned_key(string.format("%02X", ep_id))
end

local function create_child_devices(driver, device)
  local children_amount = get_children_amount(device)
  for i = 2, children_amount+1, 1 do
    local name = string.sub(device.label, 1, 9)
    if find_child(device, i) == nil then
      local metadata = {
        type = "EDGE_CHILD",
        parent_assigned_child_key = string.format("%02X", i),
        label = name ..' '..i,
        profile = "basic-switch-no-firmware-update",
        parent_device_id = device.id,
        vendor_provided_label = name ..' '..i,
      }
      driver:try_create_device(metadata)
    end
  end
  device:refresh()
end

--Handler Send Command 
local function send_on_handle(driver, device)
  if device.network_type ~= stDevice.NETWORK_TYPE_CHILD then
    device:send(OnOff.server.commands.On(device):to_endpoint(device.fingerprinted_endpoint_id))
  else
    device:send(OnOff.server.commands.On(device):to_endpoint(tonumber(device.parent_assigned_child_key)))
  end
end

local function send_off_handle(driver, device)
  if device.network_type ~= stDevice.NETWORK_TYPE_CHILD then
    device:send(OnOff.server.commands.Off(device):to_endpoint(device.fingerprinted_endpoint_id))
  else
    device:send(OnOff.server.commands.Off(device):to_endpoint(tonumber(device.parent_assigned_child_key)))
  end
end

--Handler Attribute
local function attribute_handle(driver, device, value, zb_rx)
  local attr = capabilities.switch.switch
  device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, value.value and attr.on() or attr.off())
end

--LifeCycle
local function device_info_changed(driver, device, event, args)
  device:send(OnOff.attributes.OnOff:read(device):to_endpoint(device.fingerprinted_endpoint_id))
end

local function device_added(driver, device)
  if device.network_type ~= stDevice.NETWORK_TYPE_CHILD then
    create_child_devices(driver, device)
  end
end

local function device_init(driver, device, event)
  device:set_find_child(find_child)
end

--Driver
local HanssemSwitch = {
  NAME = "Zigbee Hanssem Switch",
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = send_on_handle,
      [capabilities.switch.commands.off.NAME] = send_off_handle
    },
  },
  zigbee_handlers = {
    attr = {
      [OnOff.ID] = {
        [OnOff.attributes.OnOff.ID] = attribute_handle
      }
    }
  },
  lifecycle_handlers = {
    added = device_added,
    init = device_init,
    infoChanged = device_info_changed
  },
  can_handle = can_handle_hanssem_switch
}

return HanssemSwitch