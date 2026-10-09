local cluster_base = require "st.matter.cluster_base"
local data_types = require "st.matter.data_types"
local TLVParser = require "st.matter.TLV.TLVParser"

local CurrentErrorList = {
  ID = 0x0002,
  NAME = "CurrentErrorList",
  base_type = require "st.matter.data_types.Array",
  element_type = require "embedded_clusters.ClosureControl.types.ClosureErrorEnum",
}

function CurrentErrorList:augment_type(data_type_obj)
  for i, v in ipairs(data_type_obj.elements) do
    data_type_obj.elements[i] = data_types.validate_or_build_type(v, CurrentErrorList.element_type)
  end
end

function CurrentErrorList:new_value(...)
  local o = self.base_type(table.unpack({...}))
  self:augment_type(o)
  return o
end

function CurrentErrorList:read(device, endpoint_id)
  return cluster_base.read(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil
  )
end

function CurrentErrorList:subscribe(device, endpoint_id)
  return cluster_base.subscribe(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil
  )
end

function CurrentErrorList:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

function CurrentErrorList:build_test_report_data(
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

function CurrentErrorList:deserialize(tlv_buf)
  local data = TLVParser.decode_tlv(tlv_buf)
  self:augment_type(data)
  return data
end

setmetatable(CurrentErrorList, {__call = CurrentErrorList.new_value, __index = CurrentErrorList.base_type})
return CurrentErrorList
