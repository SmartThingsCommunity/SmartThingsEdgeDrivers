local cluster_base = require "st.matter.cluster_base"
local data_types = require "st.matter.data_types"
local TLVParser = require "st.matter.TLV.TLVParser"

local StartUpMode = {
  ID = 0x0002,
  NAME = "StartUpMode",
  base_type = require "st.matter.data_types.Uint8",
}

function StartUpMode:new_value(...)
  local o = self.base_type(table.unpack({...}))

  return o
end

function StartUpMode:read(device, endpoint_id)
  return cluster_base.read(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil
  )
end

function StartUpMode:write(device, endpoint_id, value)
  local data = data_types.validate_or_build_type(value, self.base_type)

  return cluster_base.write(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil,
    data
  )
end

function StartUpMode:subscribe(device, endpoint_id)
  return cluster_base.subscribe(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil
  )
end

function StartUpMode:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

function StartUpMode:build_test_report_data(
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

function StartUpMode:deserialize(tlv_buf)
  local data = TLVParser.decode_tlv(tlv_buf)

  return data
end

setmetatable(StartUpMode, {__call = StartUpMode.new_value, __index = StartUpMode.base_type})
return StartUpMode

