-- Copyright 2021 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0
local data_types = require "st.zigbee.data_types"
local utils = require "st.zigbee.utils"
local zdo_commands = require "st.zigbee.zdo.commands"

local zdo_messages = {}

--- A class representing a zigbee ZDO header
--- @class st.zigbee.zdo.Header
---
--- @field public NAME string "ZDOHeader" used for printing
--- @field public seqno st.zigbee.data_types.Uint8 the sequence number for the Zigbee message
local ZdoHeader = {
    NAME = "ZDOHeader",
}
ZdoHeader.__index = ZdoHeader
zdo_messages.ZdoHeader = ZdoHeader

--- A function to take a stream of bytes and parse a Zigbee Zdo header
--- @param buf Reader The buf positioned at the beginning of the bytes representing the ZdoHeader
--- @return st.zigbee.zdo.Header a new instance of the ZdoHeader parsed from the bytes
function ZdoHeader.deserialize(buf)
    local s = {}
    s.seqno = data_types.Uint8.deserialize(buf, "seqno")
    setmetatable(s, ZdoHeader)
    return s
end

--- A helper function used by common code to get all the component pieces of this message frame
---@return table An array formatted table with each component field in the order their bytes should be serialized
function ZdoHeader:get_fields()
    return { self.seqno }
end

--- A function to return the total length in bytes this frame uses when serialized
--- @return number the length in bytes of this frame
function ZdoHeader:get_length() end
ZdoHeader.get_length = utils.length_from_fields

--- A function for serializing this ZdoHeader
--- @return string This message frame serialized
ZdoHeader._serialize = utils.serialize_from_fields

--- A function for printing in a human readable format
--- @return string A human readable representation of this message frame
function ZdoHeader:pretty_print() end
ZdoHeader.pretty_print = utils.print_from_fields
ZdoHeader.__tostring = ZdoHeader.pretty_print

--- This is a function to build a Zdo header from its individual components
--- @param orig table UNUSED This is the ZclMessageRx object when called with the syntax ZclMessageRx(...)
--- @param seqno st.zigbee.data_types.Uint8 the sequence number for the ZDO header
--- @return st.zigbee.zdo.Header The constructed ZdoHeader
function ZdoHeader.from_values(orig, seqno)
    local out = {}
    out.seqno = data_types.validate_or_build_type(seqno, data_types.Uint8, "seqno")
    out.seqno.field_name = "seqno"
    setmetatable(out, ZdoHeader)
    return out
end

setmetatable(zdo_messages.ZdoHeader, { __call = zdo_messages.ZdoHeader.from_values })

--- A class representing a received zigbee ZDO message (device -> hub).
--- @class st.zigbee.zdo.MessageBody
---
--- @field public NAME string "ZdoMessageRx" used for printing
--- @field public type st.zigbee.data_types.Uint8 message type (internal use only)
--- @field public address_header st.zigbee.AddressHeader The addressing information for this message
--- @field public lqi st.zigbee.data_types.Uint8 The lqi of this message
--- @field public rssi st.zigbee.data_types.Int8 The rssi of this message
--- @field public zdo_header st.zigbee.zdo.Header  The ZdoHeader for this message
--- @field public body st.zigbee.zdo.MessageBody The message body. This is a message frame that must implement serialize, get_length, pretty_print, etc.
local ZdoMessageBody = {
    NAME = "ZDOMessageBody",
}
ZdoMessageBody.__index = ZdoMessageBody
zdo_messages.ZdoMessageBody = ZdoMessageBody

--- A function to take a stream of bytes and parse a received Zigbee Zdo message (device -> hub)
--- @param parent table A parent table for the class that includes the type, address_header, lqi, rssi, and body_length
--- @param buf Reader The buf positioned at the beginning of the bytes representing the ZdoHeader
--- @return st.zigbee.zdo.MessageBody a new instance of the ZdoMessageRx parsed from the bytes
function ZdoMessageBody.deserialize(parent, buf)
    local s = {}
    s.zdo_header = zdo_messages.ZdoHeader.deserialize(buf)
    -- there is a bug in hub FW that causes the zdo message payload to have an invalid first byte
    -- and a missing last byte. Default to adding in a 1, which is a good default for the mgmt_bind_response
    -- binding table entry endpoint_id
    local version = require "version"
    if version.rpc == 8 then
      buf.buf = buf.buf .. "\01"
      buf:seek(1)
    end
    s.zdo_body = zdo_commands.parse_zdo_command(parent.address_header.cluster.value, buf)

    setmetatable(s, ZdoMessageBody)
    return s
end

--- A helper function used by common code to get all the component pieces of this message frame
---@return table An array formatted table with each component field in the order their bytes should be serialized
function ZdoMessageBody:get_fields()
    return {
        self.zdo_header,
        self.zdo_body
    }
end

--- A function to return the total length in bytes this frame uses when serialized
--- @return number the length in bytes of this frame
function ZdoMessageBody:get_length() end
ZdoMessageBody.get_length = utils.length_from_fields

--- A function for serializing this Zdo Message
--- @return string the bytes representing this message
ZdoMessageBody._serialize = utils.serialize_from_fields

--- A function for printing in a human readable format
--- @return string A human readable representation of this message frame
function ZdoMessageBody:pretty_print() end
ZdoMessageBody.pretty_print = utils.print_from_fields
ZdoMessageBody.__tostring = ZdoMessageBody.pretty_print

--- This is a function to build an zdo rx message from its individual components
--- @param orig table UNUSED This is the ZdoMessageRx object when called with the syntax ZdoMessageRx(...)
--- @param data_table table a table containing the fields of this ZdoMessageRx. address_header, zdo_header, and body are required. type, lqi, rssi are optional with defaults
--- @return st.zigbee.zdo.MessageBody The constructed ZdoMessageRx
function ZdoMessageBody.from_values(orig, data_table)
    if data_table.zdo_header == nil then
        -- Just set seqno to 0
        data_table.zdo_header = zdo_messages.ZdoHeader(0)
    end
    if data_table.zdo_body == nil then
        error(string.format("%s requires valid body", orig.NAME), 2)
    end
    setmetatable(data_table, ZdoMessageBody)
    return data_table
end

setmetatable(zdo_messages.ZdoMessageBody, { __call = zdo_messages.ZdoMessageBody.from_values })

return zdo_messages
