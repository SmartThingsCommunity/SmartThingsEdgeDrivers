local cluster_base = require "st.matter.cluster_base"
local data_types = require "st.matter.data_types"
local TLVParser = require "st.matter.TLV.TLVParser"

local ApparentPower = {
  ID = 0x000A,
  NAME = "ApparentPower",
  base_type = data_types.Int64,
}

ApparentPower.enum_fields = {}

function ApparentPower:augment_type(base_type_obj)
  base_type_obj.field_name = self.NAME
  base_type_obj.pretty_print = self.pretty_print
end

function ApparentPower.pretty_print(value_obj)
  return string.format("%s.%s", value_obj.field_name or value_obj.NAME, ApparentPower.enum_fields[value_obj.value])
end

function ApparentPower:new_value(...)
  local o = self.base_type(table.unpack({...}))
  self:augment_type(o)
  return o
end

function ApparentPower:read(device, endpoint_id)
  return cluster_base.read(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil --event_id
  )
end

function ApparentPower:subscribe(device, endpoint_id)
  return cluster_base.subscribe(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil --event_id
  )
end

function ApparentPower:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

function ApparentPower:build_test_report_data(
  device,
  endpoint_id,
  value,
  status
)
  local data = data_types.validate_or_build_type(value, self.base_type)
  self:augment_type(data)
  return cluster_base.build_test_report_data(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    data,
    status
  )
end

function ApparentPower:deserialize(tlv_buf)
  local data = TLVParser.decode_tlv(tlv_buf)
  self:augment_type(data)
  return data
end

setmetatable(ApparentPower, {__call = ApparentPower.new_value})
return ApparentPower
