local cluster_base = require "st.matter.cluster_base"
local data_types = require "st.matter.data_types"
local TLVParser = require "st.matter.TLV.TLVParser"

local UserCodeTemporaryDisableTime = {
  ID = 0x0031,
  NAME = "UserCodeTemporaryDisableTime",
  base_type = require "st.matter.data_types.Uint8",
}

function UserCodeTemporaryDisableTime:new_value(...)
  local o = self.base_type(table.unpack({...}))

  return o
end

function UserCodeTemporaryDisableTime:read(device, endpoint_id)
  return cluster_base.read(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil
  )
end

function UserCodeTemporaryDisableTime:write(device, endpoint_id, value)
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

function UserCodeTemporaryDisableTime:subscribe(device, endpoint_id)
  return cluster_base.subscribe(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil
  )
end

function UserCodeTemporaryDisableTime:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

function UserCodeTemporaryDisableTime:build_test_report_data(
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

function UserCodeTemporaryDisableTime:deserialize(tlv_buf)
  local data = TLVParser.decode_tlv(tlv_buf)

  return data
end

setmetatable(UserCodeTemporaryDisableTime, {__call = UserCodeTemporaryDisableTime.new_value, __index = UserCodeTemporaryDisableTime.base_type})
return UserCodeTemporaryDisableTime