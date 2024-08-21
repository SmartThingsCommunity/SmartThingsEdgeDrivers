local cluster_base = require "st.matter.cluster_base"
local data_types = require "st.matter.data_types"
local TLVParser = require "st.matter.TLV.TLVParser"

local SessionDuration = {
  ID = 0x0041,
  NAME = "SessionDuration",
  base_type = data_types.Uint32,
}

SessionDuration.enum_fields = {}

function SessionDuration:augment_type(base_type_obj)
  base_type_obj.field_name = self.NAME
  base_type_obj.pretty_print = self.pretty_print
end

function SessionDuration.pretty_print(value_obj)
  return string.format("%s.%s", value_obj.field_name or value_obj.NAME, SessionDuration.enum_fields[value_obj.value])
end

function SessionDuration:new_value(...)
  local o = self.base_type(table.unpack({...}))
  self:augment_type(o)
  return o
end

function SessionDuration:read(device, endpoint_id)
  return cluster_base.read(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil --event_id
  )
end

function SessionDuration:subscribe(device, endpoint_id)
  return cluster_base.subscribe(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil --event_id
  )
end

function SessionDuration:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

function SessionDuration:build_test_report_data(
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

function SessionDuration:deserialize(tlv_buf)
  local data = TLVParser.decode_tlv(tlv_buf)
  self:augment_type(data)
  return data
end

setmetatable(SessionDuration, {__call = SessionDuration.new_value})
return SessionDuration
