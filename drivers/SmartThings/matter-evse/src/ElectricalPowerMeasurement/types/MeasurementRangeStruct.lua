local data_types = require "st.matter.data_types"
local StructureABC = require "st.matter.data_types.base_defs.StructureABC"
local MeasurementTypeEnum = require "ElectricalPowerMeasurement.types.MeasurementTypeEnum"
local MeasurementRangeStruct = {}
local new_mt = StructureABC.new_mt({NAME = "MeasurementRangeStruct", ID = data_types.name_to_id_map["Structure"]})

MeasurementRangeStruct.field_defs = {
  {
    data_type = MeasurementTypeEnum,
    field_id = 0,
    name = "measurement_type",
  },
  {
    data_type = data_types.Int64,
    field_id = 1,
    name = "min",
    is_nullable = false,
    is_optional = false,
  },
  {
    data_type = data_types.Int64,
    field_id = 2,
    name = "max",
    is_nullable = false,
    is_optional = false,
  },
  {
    data_type = data_types.Uint32,
    field_id = 3,
    name = "start_timestamp",
    is_nullable = false,
    is_optional = false,
  },
  {
    data_type = data_types.Uint32,
    field_id = 4,
    name = "end_timestamp",
    is_nullable = false,
    is_optional = false,
  },
  {
    data_type = data_types.Uint32,
    field_id = 5,
    name = "min_timestamp",
    is_nullable = false,
    is_optional = false,
  },
  {
    data_type = data_types.Uint32,
    field_id = 6,
    name = "max_timestamp",
    is_nullable = false,
    is_optional = false,
  },
  {
    data_type = data_types.Uint64,
    field_id = 7,
    name = "start_systime",
  },
  {
    data_type = data_types.Uint64,
    field_id = 8,
    name = "end_systime",
  },
  {
    data_type = data_types.Uint64,
    field_id = 9,
    name = "min_systime",
  },
  {
    data_type = data_types.Uint64,
    field_id = 10,
    name = "max_systime",
  },
}

MeasurementRangeStruct.init = function(cls, tbl)
    local o = {}
    o.elements = {}
    o.num_elements = 0
    setmetatable(o, new_mt)
    for idx, field_def in ipairs(cls.field_defs) do --Note: idx is 1 when field_id is 0
      if (not field_def.is_optional or not field_def.is_nullable) and not tbl[field_def.name] then
        error("Missing non optional or non_nullable field: " .. field_def.name)
      else
        o.elements[field_def.name] = data_types.validate_or_build_type(tbl[field_def.name], field_def.data_type, field_def.name)
        o.elements[field_def.name].field_id = field_def.field_id
        o.num_elements = o.num_elements + 1
      end
    end
    return o
end

MeasurementRangeStruct.serialize = function(self, buf, include_control, tag)
  return data_types['Structure'].serialize(self.elements, buf, include_control, tag)
end

new_mt.__call = MeasurementRangeStruct.init
new_mt.__index.serialize = MeasurementRangeStruct.serialize

MeasurementRangeStruct.augment_type = function(self, val)
  local elems = {}
  for _, v in ipairs(val.elements) do
    for _, field_def in ipairs(self.field_defs) do
      if field_def.field_id == v.field_id and
         field_def.is_nullable and
         (v.value == nil and v.elements == nil) then
        elems[field_def.name] = data_types.validate_or_build_type(v, data_types.Null, field_def.field_name)
      elseif field_def.field_id == v.field_id and not
        (field_def.is_optional and v.value == nil) then
        elems[field_def.name] = data_types.validate_or_build_type(v, field_def.data_type, field_def.field_name)
        if field_def.array_type ~= nil then
          for i, e in ipairs(elems[field_def.name].elements) do
            elems[field_def.name].elements[i] = data_types.validate_or_build_type(e, field_def.array_type)
          end
        end
      end
    end
  end
  val.elements = elems
  setmetatable(val, new_mt)
end

setmetatable(MeasurementRangeStruct, new_mt)

return MeasurementRangeStruct