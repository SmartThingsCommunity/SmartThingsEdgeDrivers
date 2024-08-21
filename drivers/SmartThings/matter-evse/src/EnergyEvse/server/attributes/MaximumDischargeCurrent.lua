local cluster_base = require "st.matter.cluster_base"
local data_types = require "st.matter.data_types"
local TLVParser = require "st.matter.TLV.TLVParser"

local MaximumDischargeCurrent = {
  ID = 0x0008,
  NAME = "MaximumDischargeCurrent",
  base_type = data_types.Int64,
}

MaximumDischargeCurrent.enum_fields = {
}

function MaximumDischargeCurrent:augment_type(base_type_obj)
  base_type_obj.field_name = self.NAME
  base_type_obj.pretty_print = self.pretty_print
end

function MaximumDischargeCurrent.pretty_print(value_obj)
  return string.format("%s.%s", value_obj.field_name or value_obj.NAME, MaximumDischargeCurrent.enum_fields[value_obj.value])
end

function MaximumDischargeCurrent:new_value(...)
  local o = self.base_type(table.unpack({...}))
  self:augment_type(o)
  return o
end

function MaximumDischargeCurrent:read(device, endpoint_id)
  return cluster_base.read(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil --event_id
  )
end

function MaximumDischargeCurrent:subscribe(device, endpoint_id)
  return cluster_base.subscribe(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil --event_id
  )
end

function MaximumDischargeCurrent:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

function MaximumDischargeCurrent:build_test_report_data(
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

function MaximumDischargeCurrent:deserialize(tlv_buf)
  local data = TLVParser.decode_tlv(tlv_buf)
  self:augment_type(data)
  return data
end

setmetatable(MaximumDischargeCurrent, {__call = MaximumDischargeCurrent.new_value})
return MaximumDischargeCurrent

