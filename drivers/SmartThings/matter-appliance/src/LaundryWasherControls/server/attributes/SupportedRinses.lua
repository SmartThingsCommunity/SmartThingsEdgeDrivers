local cluster_base = require "st.matter.cluster_base"
local data_types = require "st.matter.data_types"
local TLVParser = require "st.matter.TLV.TLVParser"

local SupportedRinses = {
  ID = 0x0003,
  NAME = "SupportedRinses",
  base_type = require "st.matter.data_types.Array",
  element_type = require "LaundryWasherControls.types.NumberOfRinsesEnum",
}

function SupportedRinses:augment_type(data_type_obj)
  for i, v in ipairs(data_type_obj.elements) do
    data_type_obj.elements[i] = data_types.validate_or_build_type(v, SupportedRinses.element_type)
  end
end

function SupportedRinses:new_value(...)
  local o = self.base_type(table.unpack({...}))
  self:augment_type(o)
  return o
end

function SupportedRinses:read(device, endpoint_id)
  return cluster_base.read(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil
  )
end

function SupportedRinses:subscribe(device, endpoint_id)
  return cluster_base.subscribe(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil
  )
end

function SupportedRinses:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

function SupportedRinses:build_test_report_data(
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

function SupportedRinses:deserialize(tlv_buf)
  local data = TLVParser.decode_tlv(tlv_buf)
  self:augment_type(data)
  return data
end

setmetatable(SupportedRinses, {__call = SupportedRinses.new_value, __index = SupportedRinses.base_type})
return SupportedRinses
