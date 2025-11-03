local cluster_base = require "st.matter.cluster_base"
local data_types = require "st.matter.data_types"
local TLVParser = require "st.matter.TLV.TLVParser"

local AcceptedCommandList = {
  ID = 0xFFF9,
  NAME = "AcceptedCommandList",
  base_type = require "st.matter.data_types.Array",
  element_type = require "st.matter.data_types.Uint32",
}

function AcceptedCommandList:augment_type(data_type_obj)
  for i, v in ipairs(data_type_obj.elements) do
    data_type_obj.elements[i] = data_types.validate_or_build_type(v, AcceptedCommandList.element_type)
  end
end

function AcceptedCommandList:new_value(...)
  local o = self.base_type(table.unpack({...}))

  return o
end

function AcceptedCommandList:read(device, endpoint_id)
  return cluster_base.read(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil
  )
end

function AcceptedCommandList:subscribe(device, endpoint_id)
  return cluster_base.subscribe(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil
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

  return data
end

setmetatable(AcceptedCommandList, {__call = AcceptedCommandList.new_value, __index = AcceptedCommandList.base_type})
return AcceptedCommandList

