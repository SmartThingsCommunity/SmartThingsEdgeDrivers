-- Copyright 2025 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
local data_types = require "st.zigbee.data_types"
local utils = require "st.zigbee.utils"

local unbind_request = {}

unbind_request.UNBIND_REQUEST_CLUSTER_ID = 0x0022
unbind_request.ADDRESS_MODE_16_BIT = 0x01
unbind_request.ADDRESS_MODE_64_BIT = 0x03

local UnbindRequest = {
  ID = unbind_request.UNBIND_REQUEST_CLUSTER_ID,
  NAME = "UnbindRequest",
}
UnbindRequest.__index = UnbindRequest
unbind_request.UnbindRequest = UnbindRequest

function UnbindRequest.deserialize(buf)
  local self = {}
  setmetatable(self, UnbindRequest)

  local fields = {
    { name = "src_address", type = data_types.IeeeAddress },
    { name = "src_endpoint", type = data_types.Uint8 },
    { name = "cluster_id", type = data_types.ClusterId },
    { name = "dest_addr_mode", type = data_types.Uint8 },
  }
  utils.deserialize_field_list(self, fields, buf)

  if self.dest_addr_mode.value == unbind_request.ADDRESS_MODE_16_BIT then
    self.dest_address = data_types.Uint16.deserialize(buf)
  else
    self.dest_address = data_types.IeeeAddress.deserialize(buf)
    self.dest_endpoint = data_types.Uint8.deserialize(buf)
  end
  return self
end

--- A helper function used by common code to get all the component pieces of this message frame
function UnbindRequest:get_fields()
  local out = {}
  out[#out + 1] = self.src_address
  out[#out + 1] = self.src_endpoint
  out[#out + 1] = self.cluster_id
  out[#out + 1] = self.dest_addr_mode
  out[#out + 1] = self.dest_address
  if self.dest_addr_mode.value == unbind_request.ADDRESS_MODE_64_BIT then
    out[#out + 1] = self.dest_endpoint
  end
  return out
end

UnbindRequest.get_length = utils.length_from_fields
UnbindRequest._serialize = utils.serialize_from_fields
UnbindRequest.pretty_print = utils.print_from_fields
UnbindRequest.__tostring = UnbindRequest.pretty_print
function UnbindRequest.from_values(orig, src_address, src_endpoint, cluster_id, dest_addr_mode, dest_address,
                                   dest_endpoint)
  local out = {}
  if src_address == nil or src_endpoint == nil or cluster_id == nil or dest_addr_mode == nil or dest_address == nil then
    error("Missing necessary values for bind request", 2)
  end

  out.src_address = data_types.validate_or_build_type(src_address, data_types.IeeeAddress, "src_address")
  out.src_endpoint = data_types.validate_or_build_type(src_endpoint, data_types.Uint8, "src_endpoint")
  out.cluster_id = data_types.validate_or_build_type(cluster_id, data_types.ClusterId, "cluster")
  out.dest_addr_mode = data_types.validate_or_build_type(dest_addr_mode, data_types.Uint8, "dest_addr_mode")
  if (out.dest_addr_mode.value == unbind_request.ADDRESS_MODE_16_BIT) then
    out.dest_address = data_types.validate_or_build_type(dest_address, data_types.Uint16, "dest_address")
  elseif out.dest_addr_mode.value == unbind_request.ADDRESS_MODE_64_BIT then
    out.dest_address = data_types.validate_or_build_type(dest_address, data_types.IeeeAddress, "dest_address")
    out.dest_endpoint = data_types.validate_or_build_type(dest_endpoint, data_types.Uint8, "dest_endpoint")
  else
    error(string.format("Unrecognized destination address mode: %d", out.dest_addr_mode.value), 2)
  end

  setmetatable(out, UnbindRequest)
  return out
end

setmetatable(unbind_request.UnbindRequest, { __call = unbind_request.UnbindRequest.from_values })

return unbind_request
