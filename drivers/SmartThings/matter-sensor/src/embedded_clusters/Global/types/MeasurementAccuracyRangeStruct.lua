local data_types = require "st.matter.data_types"
local StructureABC = require "st.matter.data_types.base_defs.StructureABC"

local MeasurementAccuracyRangeStruct = {}
local new_mt = StructureABC.new_mt({NAME = "MeasurementAccuracyRangeStruct", ID = data_types.name_to_id_map["Structure"]})

MeasurementAccuracyRangeStruct.field_defs = {
  {
    name = "range_min",
    field_id = 0,
    is_nullable = false,
    is_optional = false,
    data_type = require "st.matter.data_types.Int64",
  },
  {
    name = "range_max",
    field_id = 1,
    is_nullable = false,
    is_optional = false,
    data_type = require "st.matter.data_types.Int64",
  },
  {
    name = "percent_max",
    field_id = 2,
    is_nullable = false,
    is_optional = true,
    data_type = require "st.matter.data_types.Uint16",
  },
  {
    name = "percent_min",
    field_id = 3,
    is_nullable = false,
    is_optional = true,
    data_type = require "st.matter.data_types.Uint16",
  },
  {
    name = "percent_typical",
    field_id = 4,
    is_nullable = false,
    is_optional = true,
    data_type = require "st.matter.data_types.Uint16",
  },
  {
    name = "fixed_max",
    field_id = 5,
    is_nullable = false,
    is_optional = true,
    data_type = require "st.matter.data_types.Uint64",
  },
  {
    name = "fixed_min",
    field_id = 6,
    is_nullable = false,
    is_optional = true,
    data_type = require "st.matter.data_types.Uint64",
  },
  {
    name = "fixed_typical",
    field_id = 7,
    is_nullable = false,
    is_optional = true,
    data_type = require "st.matter.data_types.Uint64",
  },
}

MeasurementAccuracyRangeStruct.init = function(cls, tbl)
    local o = {}
    o.elements = {}
    o.num_elements = 0
    setmetatable(o, new_mt)
    for _idx, field_def in ipairs(cls.field_defs) do
      if (not field_def.is_optional and not field_def.is_nullable) and not tbl[field_def.name] then
        error("Missing non optional or non_nullable field: " .. field_def.name)
      elseif not (field_def.is_optional and tbl[field_def.name] == nil) then
        o.elements[field_def.name] = data_types.validate_or_build_type(tbl[field_def.name], field_def.data_type, field_def.name)
        o.elements[field_def.name].field_id = field_def.field_id
        o.num_elements = o.num_elements + 1
      end
    end
    return o
end

MeasurementAccuracyRangeStruct.serialize = function(self, buf, include_control, tag)
  return data_types['Structure'].serialize(self.elements, buf, include_control, tag)
end

new_mt.__call = MeasurementAccuracyRangeStruct.init
new_mt.__index.serialize = MeasurementAccuracyRangeStruct.serialize

MeasurementAccuracyRangeStruct.augment_type = function(self, val)
  local elems = {}
  local num_elements = 0
  for _, v in pairs(val.elements) do
    for _, field_def in ipairs(self.field_defs) do
      if field_def.field_id == v.field_id and
         field_def.is_nullable and
         (v.value == nil and v.elements == nil) then
        elems[field_def.name] = data_types.validate_or_build_type(v, data_types.Null, field_def.field_name)
        num_elements = num_elements + 1
      elseif field_def.field_id == v.field_id and not
        (field_def.is_optional and v.value == nil and v.elements == nil) then
        elems[field_def.name] = data_types.validate_or_build_type(v, field_def.data_type, field_def.field_name)
        num_elements = num_elements + 1
        if field_def.element_type ~= nil then
          for i, e in ipairs(elems[field_def.name].elements) do
            elems[field_def.name].elements[i] = data_types.validate_or_build_type(e, field_def.element_type)
          end
        end
      end
    end
  end
  val.elements = elems
  val.num_elements = num_elements
  setmetatable(val, new_mt)
end

setmetatable(MeasurementAccuracyRangeStruct, new_mt)

return MeasurementAccuracyRangeStruct
