local cluster_base = require "st.matter.cluster_base"
local data_types = require "st.matter.data_types"
local TLVParser = require "st.matter.TLV.TLVParser"

local AcceptedCommandList = {
  ID = 0xFFF9,
  NAME = "AcceptedCommandList",
  base_type = require "st.matter.data_types.Array",
  element_type = require "st.matter.data_types.Uint32"
}

AcceptedCommandList.enum_fields = {}

function AcceptedCommandList:augment_type(base_type_obj)
  base_type_obj.field_name = self.NAME
  base_type_obj.pretty_print = self.pretty_print
end

function AcceptedCommandList.pretty_print(value_obj)
  return string.format("%s.%s", value_obj.field_name or value_obj.NAME, AcceptedCommandList.enum_fields[value_obj.value])
end

function AcceptedCommandList:new_value(...)
  local o = self.base_type(table.unpack({...}))
  self:augment_type(o)
  return o
end

function AcceptedCommandList:read(device, endpoint_id)
  return cluster_base.read(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil --event_id
  )
end

function AcceptedCommandList:subscribe(device, endpoint_id)
  return cluster_base.subscribe(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil --event_id
  )
end

function AcceptedCommandList:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

function AcceptedCommandList:build_test_report_data(
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

function AcceptedCommandList:deserialize(tlv_buf)
  local data = TLVParser.decode_tlv(tlv_buf)
  self:augment_type(data)
  return data
end

setmetatable(AcceptedCommandList, {__call = AcceptedCommandList.new_value})
return AcceptedCommandList
