local cluster_base = require "st.matter.cluster_base"
local data_types = require "st.matter.data_types"
local TLVParser = require "st.matter.TLV.TLVParser"

local CurrentSensitivityLevel = {
  ID = 0x0000,
  NAME = "CurrentSensitivityLevel",
  base_type = require "st.matter.data_types.Uint8",
}

function CurrentSensitivityLevel:new_value(...)
  local o = self.base_type(table.unpack({...}))

  return o
end

function CurrentSensitivityLevel:read(device, endpoint_id)
  return cluster_base.read(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil --event_id
  )
end

function CurrentSensitivityLevel:write(device, endpoint_id, value)
  local data = data_types.validate_or_build_type(value, self.base_type)

  return cluster_base.write(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil, --event_id
    data
  )
end

function CurrentSensitivityLevel:subscribe(device, endpoint_id)
  return cluster_base.subscribe(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil --event_id
  )
end

function CurrentSensitivityLevel:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

function CurrentSensitivityLevel:build_test_report_data(
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

function CurrentSensitivityLevel:deserialize(tlv_buf)
  local data = TLVParser.decode_tlv(tlv_buf)

  return data
end

setmetatable(CurrentSensitivityLevel, {__call = CurrentSensitivityLevel.new_value, __index = CurrentSensitivityLevel.base_type})
return CurrentSensitivityLevel
