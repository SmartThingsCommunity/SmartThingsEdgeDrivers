local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local data_types = require "st.zigbee.data_types"
local zcl_messages = require "st.zigbee.zcl"
local messages = require "st.zigbee.messages"
local zb_const = require "st.zigbee.constants"
local read_attribute = require "st.zigbee.zcl.global_commands.read_attribute"

local TUYA_MFR_HEADER = "_TZ"

local function is_multi_endpoint(device)
  local main_endpoint = device:get_endpoint(clusters.OnOff.ID)
  for _, ep in ipairs(device.zigbee_endpoints) do
    if ep.id ~= main_endpoint then
      return true
    end
  end
  return false
end

local function is_tuya_products(opts, driver, device)
  if string.sub(device:get_manufacturer(),1,3) == TUYA_MFR_HEADER and is_multi_endpoint(device) then  -- if it is a tuya device, then send the magic packet
      local subdriver = require("tuya-multi")
      return true, subdriver
  end
  return false
end

local function read_attribute_function(device, cluster_id, attr_id)
  local read_body = read_attribute.ReadAttribute( attr_id )
  local zclh = zcl_messages.ZclHeader({
    cmd = data_types.ZCLCommandId(read_attribute.ReadAttribute.ID)
  })
  local addrh = messages.AddressHeader(
      zb_const.HUB.ADDR,
      zb_const.HUB.ENDPOINT,
      device:get_short_address(),
      device:get_endpoint(clusters.Basic.ID),
      zb_const.HA_PROFILE_ID,
      clusters.Basic.ID
  )
  local message_body = zcl_messages.ZclMessageBody({
    zcl_header = zclh,
    zcl_body = read_body
  })
  return messages.ZigbeeMessageTx({
    address_header = addrh,
    body = message_body
  })
end

local do_configure = function(self, device)
  device:refresh()
  device:configure()
  local magic_spell = {0x0004, 0x0000, 0x0001, 0x0005, 0x0007, 0xfffe}
  device:send(read_attribute_function(device, clusters.Basic.ID, magic_spell))
end


local tuya_switch_handler = {
  NAME = "Tuya Switch Handler",
  lifecycle_handlers = {
      doConfigure = do_configure
  },
  supported_capabilities = {
      capabilities.switch
  },
  can_handle = is_tuya_products
}

return tuya_switch_handler