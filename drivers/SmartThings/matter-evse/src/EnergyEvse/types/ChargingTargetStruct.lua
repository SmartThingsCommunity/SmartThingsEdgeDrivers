local data_types = require "st.matter.data_types"
local StructureABC = require "st.matter.data_types.base_defs.StructureABC"

local ChargingTargetStruct = {}
local new_mt = StructureABC.new_mt({NAME = "ChargingTargetStruct", ID = data_types.name_to_id_map["Structure"]})

ChargingTargetStruct.field_defs = {
  {
    data_type = data_types.Uint16,
    field_id = 0,
    name = "target_time_minutes_past_midnight",
    is_nullable = false,
    is_optional = false,
  },
  {
    data_type = data_types.Uint8,
    field_id = 1,
    name = "target_so_c",
    is_nullable = false,
    is_optional = false,
  },
  {
    data_type = data_types.Int64,
    field_id = 2,
    name = "added_energy",
  },
}

ChargingTargetStruct.init = function(cls, tbl)
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

ChargingTargetStruct.serialize = function(self, buf, include_control, tag)
  return data_types['Structure'].serialize(self.elements, buf, include_control, tag)
end

new_mt.__call = ChargingTargetStruct.init
new_mt.__index.serialize = ChargingTargetStruct.serialize

ChargingTargetStruct.augment_type = function(self, val)
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

setmetatable(ChargingTargetStruct, new_mt)

return ChargingTargetStruct

