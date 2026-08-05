local data_types = require "st.matter.data_types"
local cluster_base = require "st.matter.cluster_base"
local TLVParser = require "st.matter.TLV.TLVParser"
local StructureABC = require "st.matter.data_types.base_defs.StructureABC"

local LockOperationError = {
  ID = 0x0003,
  NAME = "LockOperationError",
  base_type = data_types.Structure,
}

LockOperationError.field_defs = {
  {
    name = "lock_operation_type",
    field_id = 0,
    is_nullable = false,
    is_optional = false,
    data_type = require "DoorLock.types.LockOperationTypeEnum",
  },
  {
    name = "operation_source",
    field_id = 1,
    is_nullable = false,
    is_optional = false,
    data_type = require "DoorLock.types.OperationSourceEnum",
  },
  {
    name = "operation_error",
    field_id = 2,
    is_nullable = false,
    is_optional = false,
    data_type = require "DoorLock.types.OperationErrorEnum",
  },
  {
    name = "user_index",
    field_id = 3,
    is_nullable = true,
    is_optional = false,
    data_type = require "st.matter.data_types.Uint16",
  },
  {
    name = "fabric_index",
    field_id = 4,
    is_nullable = true,
    is_optional = false,
    data_type = require "st.matter.data_types.Uint8",
  },
  {
    name = "source_node",
    field_id = 5,
    is_nullable = true,
    is_optional = false,
    data_type = require "st.matter.data_types.Uint64",
  },
  {
    name = "credentials",
    field_id = 6,
    is_nullable = true,
    is_optional = true,
    data_type = require "st.matter.data_types.Array",
    element_type = require "DoorLock.types.CredentialStruct",
  },
}

function LockOperationError:augment_type(base_type_obj)
  local elems = {}
  for _, v in ipairs(base_type_obj.elements) do
    for _, field_def in ipairs(self.field_defs) do
      if field_def.field_id == v.field_id and not
        ((field_def.is_nullable or field_def.is_optional) and v.value == nil) then
        elems[field_def.name] = data_types.validate_or_build_type(v, field_def.data_type, field_def.field_name)
        if field_def.element_type ~= nil then
          for i, e in ipairs(elems[field_def.name].elements) do
            elems[field_def.name].elements[i] = data_types.validate_or_build_type(e, field_def.element_type)
          end
        end
      end
    end
  end
  base_type_obj.elements = elems
end

function LockOperationError:read(device, endpoint_id)
  return cluster_base.read(
    device,
    endpoint_id,
    self._cluster.ID,
    nil,
    self.ID
  )
end

function LockOperationError:subscribe(device, endpoint_id)
  return cluster_base.subscribe(
    device,
    endpoint_id,
    self._cluster.ID,
    nil,
    self.ID
  )
end

function LockOperationError:build_test_event_report(
  device,
  endpoint_id,
  fields,
  status
)
  local data = {}
  data.elements = {}
  data.num_elements = 0
  setmetatable(data, StructureABC.new_mt({NAME = "LockOperationErrorEventData", ID = 0x15}))
  for idx, field_def in ipairs(self.field_defs) do
    if (not field_def.is_optional and not field_def.is_nullable) and not fields[field_def.name] then
      error("Missing non optional or non_nullable field: " .. field_def.name)
    elseif fields[field_def.name] then
      data.elements[field_def.name] = data_types.validate_or_build_type(fields[field_def.name], field_def.data_type, field_def.name)
      data.elements[field_def.name].field_id = field_def.field_id
      data.num_elements = data.num_elements + 1
    end
  end
  return cluster_base.build_test_event_report(
    device,
    endpoint_id,
    self._cluster.ID,
    self.ID,
    data,
    status
  )
end

function LockOperationError:deserialize(tlv_buf)
  local data = TLVParser.decode_tlv(tlv_buf)
  self:augment_type(data)
  return data
end

function LockOperationError:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

return LockOperationError