
local cluster_base = require "st.matter.cluster_base"
local data_types = require "st.matter.data_types"
local TLVParser = require "st.matter.TLV.TLVParser"

local HarmonicPhases = {
  ID = 0x0010,
  NAME = "HarmonicPhases",
  base_type = data_types.Structure,
}

HarmonicPhases.enum_fields = {}

function HarmonicPhases:augment_type(base_type_obj)
  base_type_obj.field_name = self.NAME
  base_type_obj.pretty_print = self.pretty_print
end

function HarmonicPhases.pretty_print(value_obj)
  return string.format("%s.%s", value_obj.field_name or value_obj.NAME, HarmonicPhases.enum_fields[value_obj.value])
end

function HarmonicPhases:new_value(...)
  local o = self.base_type(table.unpack({...}))
  self:augment_type(o)
  return o
end

function HarmonicPhases:read(device, endpoint_id)
  return cluster_base.read(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil --event_id
  )
end

function HarmonicPhases:subscribe(device, endpoint_id)
  return cluster_base.subscribe(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil --event_id
  )
end

function HarmonicPhases:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

function HarmonicPhases:build_test_report_data(
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

function HarmonicPhases:deserialize(tlv_buf)
  local data = TLVParser.decode_tlv(tlv_buf)
  self:augment_type(data)
  return data
end

setmetatable(HarmonicPhases, {__call = HarmonicPhases.new_value})
return HarmonicPhases
