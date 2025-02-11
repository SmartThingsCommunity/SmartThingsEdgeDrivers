local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local data_types = require "st.zigbee.data_types"
local zcl_messages = require "st.zigbee.zcl"
local generic_body = require "st.zigbee.generic_body"
local messages = require "st.zigbee.messages"
local zb_const = require "st.zigbee.constants"
local read_attribute = require "st.zigbee.zcl.global_commands.read_attribute"

local DISCOVER_ATTR_RSP_ID = 0x0D
local DISCOVER_ATTR_RST_ID = 0x0C
local TUYA_MFR_HEADER = "_TZ"

local function is_tuya_products(opts, driver, device)
    if string.sub(device:get_manufacturer(),1,3) == TUYA_MFR_HEADER then  -- if it is a tuya device, then send the magic packet
        local subdriver = require("tuya-multi")
        return true, subdriver
    end
    return false
end

local function send_discover_command(device)
    local discover_command_payload = "\x00\x00\xff"      -- Start Attribute: 0x0000, Maximum Number: 255
    local header_args = {
      cmd = data_types.ZCLCommandId(DISCOVER_ATTR_RST_ID)
    }
    local zclh = zcl_messages.ZclHeader(header_args)
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
      zcl_body = generic_body.GenericBody(discover_command_payload)
    })
    local send_message = messages.ZigbeeMessageTx({
        address_header = addrh,
        body = message_body
    })
    device:send(send_message)
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
        device:get_endpoint(cluster_id.value),
        zb_const.HA_PROFILE_ID,
        cluster_id.value
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

local function do_payload(rx)  -- use discover attribute response payload to do read attribute payload
    local out_str = " "
    for i = 1, #rx.body_bytes do
      out_str = out_str .. string.format(" %02X", string.byte(rx.body_bytes:sub(i,i)))
    end
    local bytes = {}
    for b in out_str:gmatch("%S+") do
        table.insert(bytes, b)
    end
    table.remove(bytes, 1) -- remove first type which means discover attribute command is completed
    local result = {}
    for i = 1, #bytes, 3 do   -- remove data type information
        local low = bytes[i]
        local high = bytes[i+1]
        if high then
            local value = tonumber(high, 16) * 0x100 + tonumber(low, 16)
            table.insert(result, value)
        end
    end
    return result
end

local do_configure = function(self, device)
    device:refresh()
    device:configure()
    send_discover_command(device)
end

local function discover_response_message_handler(driver, device, zb_rx)
    if zb_rx.address_header.cluster.value == clusters.Basic.ID and zb_rx.body.zcl_header.cmd.value == DISCOVER_ATTR_RSP_ID then 
        local send_payload = do_payload(zb_rx.body.zcl_body)
        device:send(read_attribute_function(device, data_types.ClusterId(0x0000), send_payload))
    end
end

local tuya_switch_handler = {
    NAME = "Tuya Switch Handler",
    lifecycle_handlers = {
        doConfigure = do_configure
    },
    zigbee_handlers = {
        global = {
          [clusters.Basic.ID] = {
            [DISCOVER_ATTR_RSP_ID] = discover_response_message_handler,
          }
        }
      },
    supported_capabilities = {
        capabilities.switch
    },
    can_handle = is_tuya_products
}

return tuya_switch_handler
