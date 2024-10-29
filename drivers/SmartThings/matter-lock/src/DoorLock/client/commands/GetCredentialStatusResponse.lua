local data_types = require "st.matter.data_types"
local TLVParser = require "st.matter.TLV.TLVParser"

local GetCredentialStatusResponse = {}

GetCredentialStatusResponse.NAME = "GetCredentialStatusResponse"
GetCredentialStatusResponse.ID = 0x0025
GetCredentialStatusResponse.field_defs = {
  {
    name = "credential_exists",
    field_id = 0,
    is_nullable = false,
    is_optional = false,
    data_type = require "st.matter.data_types.Boolean",
  },
  {
    name = "user_index",
    field_id = 1,
    is_nullable = true,
    is_optional = false,
    data_type = require "st.matter.data_types.Uint16",
  },
  {
    name = "creator_fabric_index",
    field_id = 2,
    is_nullable = true,
    is_optional = false,
    data_type = require "st.matter.data_types.Uint8",
  },
  {
    name = "last_modified_fabric_index",
    field_id = 3,
    is_nullable = true,
    is_optional = false,
    data_type = require "st.matter.data_types.Uint8",
  },
  {
    name = "next_credential_index",
    field_id = 4,
    is_nullable = true,
    is_optional = false,
    data_type = require "st.matter.data_types.Uint16",
  },
}

function GetCredentialStatusResponse:augment_type(base_type_obj)
  local elems = {}
  for _, v in ipairs(base_type_obj.elements) do
    for _, field_def in ipairs(self.field_defs) do
      if field_def.field_id == v.field_id and
         field_def.is_nullable and
         (v.value == nil and v.elements == nil) then
        elems[field_def.name] = data_types.validate_or_build_type(v, data_types.Null, field_def.field_name)
      elseif field_def.field_id == v.field_id and not
        (field_def.is_optional and v.value == nil) then
        elems[field_def.name] = data_types.validate_or_build_type(v, field_def.data_type, field_def.field_name)
        if field_def.element_type ~= nil then
          for i, e in ipairs(elems[field_def.name].elements) do
            elems[field_def.name].elements[i] = data_types.validate_or_build_type(e, field_def.element_type)
          end
        end
      end
    end
  end
  base_type_obj.elements = elems
end

function GetCredentialStatusResponse:build_test_command_response(device, endpoint_id, credential_exists, user_index, creator_fabric_index, last_modified_fabric_index, next_credential_index, interaction_status)
  local function init(self, device, endpoint_id, credential_exists, user_index, creator_fabric_index, last_modified_fabric_index, next_credential_index)
    local out = {}
    local args = {credential_exists, user_index, creator_fabric_index, last_modified_fabric_index, next_credential_index}
    if #args > #self.field_defs then
      error(self.NAME .. " received too many arguments")
    end
    for i,v in ipairs(self.field_defs) do
      if v.is_optional and args[i] == nil then
        out[v.name] = nil
      elseif v.is_nullable and args[i] == nil then
        out[v.name] = data_types.validate_or_build_type(args[i], data_types.Null, v.name)
        out[v.name].field_id = v.field_id
      elseif not v.is_optional and args[i] == nil then
        out[v.name] = data_types.validate_or_build_type(v.default, v.data_type, v.name)
        out[v.name].field_id = v.field_id
      else
        out[v.name] = data_types.validate_or_build_type(args[i], v.data_type, v.name)
        out[v.name].field_id = v.field_id
      end
    end
    setmetatable(out, {
      __index = GetCredentialStatusResponse,
      __tostring = GetCredentialStatusResponse.pretty_print
    })
    return self._cluster:build_cluster_command(
      device,
      out,
      endpoint_id,
      self._cluster.ID,
      self.ID
    )
  end
  local self_request =  init(self, device, endpoint_id, credential_exists, user_index, creator_fabric_index, last_modified_fabric_index, next_credential_index)
  return self._cluster:build_test_command_response(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    self_request.info_blocks[1].tlv,
    interaction_status
  )
end

function GetCredentialStatusResponse:init()
  return nil
end

function GetCredentialStatusResponse:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

function GetCredentialStatusResponse:deserialize(tlv_buf)
  local data = TLVParser.decode_tlv(tlv_buf)
  self:augment_type(data)
  return data
end

setmetatable(GetCredentialStatusResponse, {__call = GetCredentialStatusResponse.init})

return GetCredentialStatusResponse
