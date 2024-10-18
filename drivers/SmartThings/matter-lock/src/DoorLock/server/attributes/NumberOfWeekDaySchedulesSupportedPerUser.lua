local cluster_base = require "st.matter.cluster_base"
local data_types = require "st.matter.data_types"
local TLVParser = require "st.matter.TLV.TLVParser"

local NumberOfWeekDaySchedulesSupportedPerUser = {
  ID = 0x0014,
  NAME = "NumberOfWeekDaySchedulesSupportedPerUser",
  base_type = require "st.matter.data_types.Uint8",
}

function NumberOfWeekDaySchedulesSupportedPerUser:new_value(...)
  local o = self.base_type(table.unpack({...}))

  return o
end

function NumberOfWeekDaySchedulesSupportedPerUser:read(device, endpoint_id)
  return cluster_base.read(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil
  )
end

function NumberOfWeekDaySchedulesSupportedPerUser:subscribe(device, endpoint_id)
  return cluster_base.subscribe(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    nil
  )
end

function NumberOfWeekDaySchedulesSupportedPerUser:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

function NumberOfWeekDaySchedulesSupportedPerUser:build_test_report_data(
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

function NumberOfWeekDaySchedulesSupportedPerUser:deserialize(tlv_buf)
  local data = TLVParser.decode_tlv(tlv_buf)

  return data
end

setmetatable(NumberOfWeekDaySchedulesSupportedPerUser, {__call = NumberOfWeekDaySchedulesSupportedPerUser.new_value, __index = NumberOfWeekDaySchedulesSupportedPerUser.base_type})
return NumberOfWeekDaySchedulesSupportedPerUser