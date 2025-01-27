local cluster_base = require "st.matter.cluster_base"
local data_types = require "st.matter.data_types"
local TLVParser = require "st.matter.TLV.TLVParser"

local UserMaximumChargeCurrent = {
  ID = 0x0009,
  NAME = "UserMaximumChargeCurrent",
  base_type = data_types.Int64,
}

UserMaximumChargeCurrent.enum_fields = {
}

function UserMaximumChargeCurrent:augment_type(base_type_obj)
  base_type_obj.field_name = self.NAME
  base_type_obj.pretty_print = self.pretty_print
end

function UserMaximumChargeCurrent.pretty_print(value_obj)
  return string.format("%s.%s", value_obj.field_name or value_obj.NAME, UserMaximumChargeCurrent.enum_fields[value_obj.value])
end

function UserMaximumChargeCurrent:new_value(...)
  local o = self.base_type(table.unpack({...}))
  self:augment_type(o)
  return o
end

function UserMaximumChargeCurrent:read(device, endpoint_id)
  return cluster_base.read(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil --event_id
  )
end

function UserMaximumChargeCurrent:write(device, endpoint_id, value)
  local data = data_types.validate_or_build_type(value, self.base_type)
  self:augment_type(data)
  return cluster_base.write(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil, --event_id
    data
  )
end

function UserMaximumChargeCurrent:subscribe(device, endpoint_id)
  return cluster_base.subscribe(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil --event_id
  )
end

function UserMaximumChargeCurrent:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

function UserMaximumChargeCurrent:build_test_report_data(
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

function UserMaximumChargeCurrent:deserialize(tlv_buf)
  local data = TLVParser.decode_tlv(tlv_buf)
  self:augment_type(data)
  return data
end

setmetatable(UserMaximumChargeCurrent, {__call = UserMaximumChargeCurrent.new_value})
return UserMaximumChargeCurrent

