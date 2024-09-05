local data_types = require "st.matter.data_types"
local TLVParser = require "st.matter.TLV.TLVParser"
local amperage_maType = require "st.matter.data_types.Int64"

local EnableCharging = {}

EnableCharging.NAME = "EnableCharging"
EnableCharging.ID = 0x0002
EnableCharging.field_defs = {
  {
    name = "charging_enabled_until",
    field_id = 0,
    optional = false,
    nullable = true,
    data_type = data_types.Uint32,
  },
  {
    name = "minimum_charge_current",
    field_id = 1,
    optional = false,
    nullable = false,
    data_type = amperage_maType,
  },
  {
    name = "maximum_charge_current",
    field_id = 2,
    optional = false,
    nullable = false,
    data_type = amperage_maType,
  },
}

function EnableCharging:build_test_command_response(device, endpoint_id, status)
  return self._cluster:build_test_command_response(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil, --tlv
    status
  )
end

function EnableCharging:init(device, endpoint_id, charging_enabled_until, minimum_charge_current, maximum_charge_current)
  local out = {}
  local args = {charging_enabled_until, minimum_charge_current, maximum_charge_current}
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
    __index = EnableCharging,
    __tostring = EnableCharging.pretty_print
  })
  return self._cluster:build_cluster_command(
    device,
    out,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    true
  )
end

function EnableCharging:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

function EnableCharging:augment_type(base_type_obj)
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

function EnableCharging:deserialize(tlv_buf)
  return TLVParser.decode_tlv(tlv_buf)
end

setmetatable(EnableCharging, {__call = EnableCharging.init})

return EnableCharging