local readAttribute = require "st.zigbee.zcl.global_commands.read_attribute"
local zclClusters = require "st.zigbee.zcl.clusters"
local zclMessages = require "st.zigbee.zcl"
local messages = require "st.zigbee.messages"
local zigbeeConstants = require "st.zigbee.constants"
local dataTypes = require "st.zigbee.data_types"

local utilities = {
  common = {},
  zcl = {},
}

---------- COMMON ----------

function utilities.common.getChild(parent, index)
  return parent:get_child_by_parent_assigned_key(string.format("%02X", index))
end

function utilities.common.findIndex(array, test)
  for i, insideValue in ipairs(array) do
    if test(insideValue) then return i end
  end
end

function utilities.common.getChildMetadata(device, key)
  local name = string.sub(device.label, 1, 9)
  return {
    type = "EDGE_CHILD",
    parent_assigned_child_key = string.format("%02X", key),
    label = name ..' '..key,
    profile = "basic-switch-no-firmware-update",
    parent_device_id = device.id,
    manufacturer = device:get_manufacturer(),
    model = device:get_model()
  }
end

---------- ZCL ----------

function utilities.zcl.createChildDevices(driver, device)
  
  local epArray = {}

  for _, ep in pairs(device.zigbee_endpoints) do
    for _, clus in ipairs(ep.server_clusters) do
      if clus == zclClusters.OnOff.ID then
        table.insert(epArray, tonumber(ep.id))
        break
      end
    end
  end

  table.sort(epArray)
  
  for i, ep in pairs(epArray) do
    if ep ~= device.fingerprinted_endpoint_id and utilities.common.getChild(device, ep) == nil then
        local metadata = utilities.common.getChildMetadata(device, ep)
        driver:try_create_device(metadata)
    end
  end
end

return utilities