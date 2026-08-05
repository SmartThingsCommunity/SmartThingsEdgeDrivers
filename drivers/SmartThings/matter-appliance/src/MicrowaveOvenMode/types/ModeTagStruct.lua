local data_types = require "st.matter.data_types"
local StructureABC = require "st.matter.data_types.base_defs.StructureABC"

local ModeTagStruct = {}
local new_mt = StructureABC.new_mt({NAME = "ModeTagStruct", ID = data_types.name_to_id_map["Structure"]})

ModeTagStruct.field_defs = {
  {
    name = "mfg_code",
    field_id = 0,
    is_nullable = false,
    is_optional = true,
    data_type = require "st.matter.data_types.Uint16",
  },
  {
    name = "value",
    field_id = 1,
    is_nullable = false,
    is_optional = false,
    data_type = require "st.matter.data_types.Uint16",
  },
}

ModeTagStruct.init = function(cls, tbl)
    local o = {}
    o.elements = {}
    o.num_elements = 0
    setmetatable(o, new_mt)
    for idx, field_def in ipairs(cls.field_defs) do --Note: idx is 1 when field_id is 0
      if (not field_def.is_optional and not field_def.is_nullable) and not tbl[field_def.name] then
        error("Missing non optional or non_nullable field: " .. field_def.name)
      else
        o.elements[field_def.name] = data_types.validate_or_build_type(tbl[field_def.name], field_def.data_type, field_def.name)
        o.elements[field_def.name].field_id = field_def.field_id
        o.num_elements = o.num_elements + 1
      end
    end
    return o
end

ModeTagStruct.serialize = function(self, buf, include_control, tag)
  return data_types['Structure'].serialize(self.elements, buf, include_control, tag)
end

new_mt.__call = ModeTagStruct.init
new_mt.__index.serialize = ModeTagStruct.serialize

ModeTagStruct.augment_type = function(self, val)
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
        (field_def.is_optional and v.value == nil) then
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

setmetatable(ModeTagStruct, new_mt)

return ModeTagStruct

