local device_lib = require "st.device"
local capabilities = require "st.capabilities"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"

local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID = 0x0009
local MFG_CODE = 0x115F

local FINGERPRINTS = {
  { mfr = "LUMI", model = "lumi.switch.n1acn1",   children = 1, child_profile = "" },
  { mfr = "LUMI", model = "lumi.switch.n2acn1",   children = 2, child_profile = "aqara-switch-child" },
  { mfr = "LUMI", model = "lumi.switch.n3acn1",   children = 3, child_profile = "aqara-switch-child" },
  { mfr = "LUMI", model = "lumi.switch.b2laus01", children = 2, child_profile = "aqara-switch-child" },
  { mfr = "LUMI", model = "lumi.switch.l2aeu1",   children = 2, child_profile = "aqara-switch-child" },
  { mfr = "LUMI", model = "lumi.switch.n2aeu1",   children = 2, child_profile = "aqara-switch-child" },
  { mfr = "LUMI", model = "lumi.switch.b2nacn01", children = 2, child_profile = "aqara-switch-child" },
  { mfr = "LUMI", model = "lumi.switch.b3n01",    children = 3, child_profile = "aqara-switch-child" }
}

local function is_aqara_products(opts, driver, device)
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

local function get_child_profile_name(device)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_model() == fingerprint.model then
      return fingerprint.child_profile
    end
  end
end

local function find_child(parent, ep_id)
  -- Buttons 1-3 report using endpoints 0x29, 0x2A, 0x2B, respectively
  if ep_id >= 0x29 then
    ep_id = ep_id - 0x28
  end
  return parent:get_child_by_parent_assigned_key(string.format("%02X", ep_id))
end

local function device_added(driver, device)
  -- Only create children for the actual Zigbee device and not the children
  if device.network_type == device_lib.NETWORK_TYPE_ZIGBEE then
    local children_amount = get_children_amount(device)
    if children_amount >= 2 then
      for i = 2, children_amount, 1 do
        if find_child(device, i) == nil then
          local name = string.format("%s%d", string.sub(device.label, 0, -2), i)
          local child_profile = get_child_profile_name(device)
          local metadata = {
            type = "EDGE_CHILD",
            label = name,
            profile = child_profile,
            parent_device_id = device.id,
            parent_assigned_child_key = string.format("%02X", i),
            vendor_provided_label = name
          }
          driver:try_create_device(metadata)
        end
      end
    end

    -- for wireless button
    device:emit_event(capabilities.button.numberOfButtons({ value = children_amount },
      { visibility = { displayed = false } }))
    device:emit_event(capabilities.powerMeter.power({ value = 0.0, unit = "W" }))
    device:emit_event(capabilities.energyMeter.energy({ value = 0.0, unit = "Wh" }))

    device:send(cluster_base.write_manufacturer_specific_attribute(device,
      PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID, MFG_CODE, data_types.Uint8, 0x01)) -- private
  elseif device.network_type == "DEVICE_EDGE_CHILD" then
    device:emit_event(capabilities.button.numberOfButtons({ value = 1 },
      { visibility = { displayed = false } }))
  end
  device:emit_event(capabilities.button.supportedButtonValues({ "pushed" },
    { visibility = { displayed = false } }))
  device:emit_event(capabilities.button.button.pushed({ state_change = false }))
end

local function device_init(self, device)
  -- for multiple switch
  if device.network_type == device_lib.NETWORK_TYPE_ZIGBEE then
    device:set_find_child(find_child)
  end
end

local aqara_multi_switch_handler = {
  NAME = "Aqara Multi Switch Handler",
  lifecycle_handlers = {
    init = device_init,
    added = device_added
  },
  can_handle = is_aqara_products
}

return aqara_multi_switch_handler
