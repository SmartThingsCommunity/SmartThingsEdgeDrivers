local data_types = require "st.matter.data_types"
local TLVParser = require "st.matter.TLV.TLVParser"

local ChangeToMode = {}

ChangeToMode.NAME = "ChangeToMode"
ChangeToMode.ID = 0x0000
ChangeToMode.field_defs = {
  {
    name = "new_mode",
    field_id = 0,
    optional = false,
    nullable = false,
    data_type = data_types.Uint8,
  },
}

function ChangeToMode:init(device, endpoint_id, new_mode)
  local out = {}
  local args = {new_mode}
  if #args > #self.field_defs then
    error(self.NAME .. " received too many arguments")
  end
  for i,v in ipairs(self.field_defs) do
    if v.optional and args[i] == nil then
      out[v.name] = nil
    elseif v.nullable and args[i] == nil then
      out[v.name] = data_types.validate_or_build_type(args[i], data_types.Null, v.name)
      out[v.name].field_id = v.field_id
    elseif not v.optional and args[i] == nil then
      out[v.name] = data_types.validate_or_build_type(v.default, v.data_type, v.name)
      out[v.name].field_id = v.field_id
    else
      out[v.name] = data_types.validate_or_build_type(args[i], v.data_type, v.name)
      out[v.name].field_id = v.field_id
    end
  end
  setmetatable(out, {
    __index = ChangeToMode,
    __tostring = ChangeToMode.pretty_print
  })
  return self._cluster:build_cluster_command(
    device,
    out,
    endpoint_id,
    self._cluster.ID,
    self.ID
  )
end

function ChangeToMode:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

function ChangeToMode:augment_type(base_type_obj)
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
      end
    end
  end
  base_type_obj.elements = elems
end

function ChangeToMode:deserialize(tlv_buf)
  return TLVParser.decode_tlv(tlv_buf)
end

setmetatable(ChangeToMode, {__call = ChangeToMode.init})

return ChangeToMode