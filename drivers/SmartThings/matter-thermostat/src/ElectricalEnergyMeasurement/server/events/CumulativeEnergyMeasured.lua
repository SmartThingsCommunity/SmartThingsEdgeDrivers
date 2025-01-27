local data_types = require "st.matter.data_types"
local cluster_base = require "st.matter.cluster_base"
local TLVParser = require "st.matter.TLV.TLVParser"
local StructureABC = require "st.matter.data_types.base_defs.StructureABC"

local CumulativeEnergyMeasured = {
  ID = 0x0000,
  NAME = "CumulativeEnergyMeasured",
  base_type = data_types.Structure,
}

CumulativeEnergyMeasured.field_defs = {
  {
    name = "energy_imported",
    field_id = 0,
    is_nullable = false,
    is_optional = true,
    data_type = require "ElectricalEnergyMeasurement.types.EnergyMeasurementStruct",
  },
  {
    name = "energy_exported",
    field_id = 1,
    is_nullable = false,
    is_optional = true,
    data_type = require "ElectricalEnergyMeasurement.types.EnergyMeasurementStruct",
  },
}

function CumulativeEnergyMeasured:augment_type(base_type_obj)
  local elems = {}
  for _, v in ipairs(base_type_obj.elements) do
    for _, field_def in ipairs(self.field_defs) do
      if field_def.field_id == v.field_id and not
        ((field_def.is_nullable or field_def.is_optional) and v.elements == nil) then
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

function CumulativeEnergyMeasured:read(device, endpoint_id)
  return cluster_base.read(
    device,
    endpoint_id,
    self._cluster.ID,
    nil, --attribute_id
    self.ID
  )
end

function CumulativeEnergyMeasured:subscribe(device, endpoint_id)
  return cluster_base.subscribe(
    device,
    endpoint_id,
    self._cluster.ID,
    nil, --attribute_id
    self.ID
  )
end

function CumulativeEnergyMeasured:build_test_event_report(
  device,
  endpoint_id,
  fields,
  status
)
  local data = {}
  data.elements = {}
  data.num_elements = 0
  setmetatable(data, StructureABC.new_mt({NAME = "CumulativeEnergyMeasuredEventData", ID = 0x15}))
  for idx, field_def in ipairs(self.field_defs) do --Note: idx is 1 when field_id is 0
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

function CumulativeEnergyMeasured:deserialize(tlv_buf)
  local data = TLVParser.decode_tlv(tlv_buf)
  self:augment_type(data)
  return data
end

function CumulativeEnergyMeasured:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

return CumulativeEnergyMeasured

