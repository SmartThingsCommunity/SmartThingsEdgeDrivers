local stDevice = require "st.device"
local capabilities = require "st.capabilities"
local zigbeeDriver = require "st.zigbee"
local zclClusters = require "st.zigbee.zcl.clusters"
local zclGlobalCommands = require "st.zigbee.zcl.global_commands"
local dataTypes = require "st.zigbee.data_types"
local Status = require "st.zigbee.generated.types.ZclStatus"

local OnOff = zclClusters.OnOff
local Basic = zclClusters.Basic

local utilities = require "hanssem/utilities"

local FINGERPRINTS = {
  { mfr = "Winners", model = "HS2-P1Z3-1" },
  { mfr = "Winners", model = "HS2-P1Z3-2" },
  { mfr = "Winners", model = "HS2-P1Z3-3" },
  { mfr = "Winners", model = "HS2-P2Z3-4" },
  { mfr = "Winners", model = "HS2-P2Z3-5" },
  { mfr = "Winners", model = "HS2-P2Z3-6" }
}

local function can_handle_hanssem_switch(opts, driver, device, ...)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

-- Handler Send Command 
function handlers_sendOn(driver, device)
  local isParent = device.network_type ~= stDevice.NETWORK_TYPE_CHILD
  local parent = isParent and device or device:get_parent_device()

  local index

  if isParent then 
    index = device.fingerprinted_endpoint_id
  else
    index = tonumber(device.parent_assigned_child_key)
  end

  parent:send(OnOff.server.commands.On(parent):to_endpoint(index))
end

function handlers_sendOff(driver, device)
  local isParent = device.network_type ~= stDevice.NETWORK_TYPE_CHILD
  local parent = isParent and device or device:get_parent_device()

  local index

  if isParent then 
    index = device.fingerprinted_endpoint_id
  else
    index = tonumber(device.parent_assigned_child_key)
  end

  parent:send(OnOff.server.commands.Off(parent):to_endpoint(index))
end

-- Handler Default Response Command
function handlers_defaultResponse(driver, parent, zb_rx)
  if parent.network_type == stDevice.NETWORK_TYPE_CHILD then return end

  local status = zb_rx.body.zcl_body.status.value
  local srcEndpoint = zb_rx.address_header.src_endpoint.value
  local device = srcEndpoint == parent.fingerprinted_endpoint_id and parent or utilities.common.getChild(parent, srcEndpoint)
  
  if status == Status.SUCCESS then
    local cmd = zb_rx.body.zcl_body.cmd.value

    if cmd == OnOff.server.commands.On.ID then
      device:emit_event(capabilities.switch.switch.on())
    elseif cmd == OnOff.server.commands.Off.ID then
      device:emit_event(capabilities.switch.switch.off())
    end
  end
end

-- Handler Attribute
function handlers_attribute(driver, parent, value, zb_rx)
  if parent.network_type == stDevice.NETWORK_TYPE_CHILD then return end
  
  local srcEndpoint = zb_rx.address_header.src_endpoint.value
  local attrValue = value.value

  local device = srcEndpoint == parent.fingerprinted_endpoint_id and parent or utilities.common.getChild(parent, srcEndpoint)

  if device == nil then return end

  if attrValue == false or attrValue == 0 then
    device:emit_event(capabilities.switch.switch.off())
  elseif attrValue == true or attrValue == 1 then
    device:emit_event(capabilities.switch.switch.on())
  end
end

-- LifeCycle
local function deviceAdded(driver, device)
  if device.network_type ~= stDevice.NETWORK_TYPE_CHILD then -- parent
    
    utilities.zcl.createChildDevices(driver, device)
    device:send(OnOff.attributes.OnOff:read(device):to_endpoint(device.fingerprinted_endpoint_id))
  else -- child
    local parent = device:get_parent_device()
    device:send(OnOff.attributes.OnOff:read(device):to_endpoint(tonumber(device.parent_assigned_child_key))) 
  end
end

local function deviceInit(driver, device)
  if device.network_type == stDevice.NETWORK_TYPE_CHILD then return end

  device:send(Basic.attributes.ManufacturerName:read(device))
  device:send(Basic.attributes.ApplicationVersion:read(device))
  device:send(Basic.attributes.ModelIdentifier:read(device))
end

-- Driver
local HanssemSwitch = {
  NAME = "Zigbee Hanssem Switch",
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = handlers_sendOn,
      [capabilities.switch.commands.off.NAME] = handlers_sendOff,
    },
  },
  zigbee_handlers = {
    global = {
      [OnOff.ID] = {
        [zclGlobalCommands.DEFAULT_RESPONSE_ID] = handlers_defaultResponse
      }
    },
    attr = {
      [OnOff.ID] = {
        [OnOff.attributes.OnOff.ID] = handlers_attribute
      },
    }
  },
  lifecycle_handlers = {
    added = deviceAdded,
    init = deviceInit
  },
  can_handle = can_handle_hanssem_switch
}

return HanssemSwitch