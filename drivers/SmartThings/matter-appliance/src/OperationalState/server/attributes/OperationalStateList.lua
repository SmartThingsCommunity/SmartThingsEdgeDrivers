local cluster_base = require "st.matter.cluster_base"
local data_types = require "st.matter.data_types"
local TLVParser = require "st.matter.TLV.TLVParser"

local OperationalStateList = {
  ID = 0x0003,
  NAME = "OperationalStateList",
  base_type = require "st.matter.data_types.Array",
  element_type = require "OperationalState.types.OperationalStateStruct",
}

function OperationalStateList:augment_type(data_type_obj)
  for i, v in ipairs(data_type_obj.elements) do
    data_type_obj.elements[i] = data_types.validate_or_build_type(v, OperationalStateList.element_type)
  end
end

function OperationalStateList:new_value(...)
  local o = self.base_type(table.unpack({...}))
  self:augment_type(o)
  return o
end

function OperationalStateList:read(device, endpoint_id)
  return cluster_base.read(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil
  )
end

function OperationalStateList:subscribe(device, endpoint_id)
  return cluster_base.subscribe(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil
  )
end

function OperationalStateList:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

function OperationalStateList:build_test_report_data(
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

function OperationalStateList:deserialize(tlv_buf)
  local data = TLVParser.decode_tlv(tlv_buf)
  self:augment_type(data)
  return data
end

setmetatable(OperationalStateList, {__call = OperationalStateList.new_value, __index = OperationalStateList.base_type})
return OperationalStateList
