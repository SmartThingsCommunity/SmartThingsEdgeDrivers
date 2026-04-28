local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local LatchControlModesBitmap = {}
local new_mt = UintABC.new_mt({NAME = "LatchControlModesBitmap", ID = data_types.name_to_id_map["Uint8"]}, 1)

LatchControlModesBitmap.BASE_MASK = 0xFFFF
LatchControlModesBitmap.REMOTE_LATCHING = 0x0001
LatchControlModesBitmap.REMOTE_UNLATCHING = 0x0002

LatchControlModesBitmap.mask_fields = {
  BASE_MASK = 0xFFFF,
  REMOTE_LATCHING = 0x0001,
  REMOTE_UNLATCHING = 0x0002,
}

LatchControlModesBitmap.is_remote_latching_set = function(self)
  return (self.value & self.REMOTE_LATCHING) ~= 0
end

LatchControlModesBitmap.set_remote_latching = function(self)
  if self.value ~= nil then
    self.value = self.value | self.REMOTE_LATCHING
  else
    self.value = self.REMOTE_LATCHING
  end
end

LatchControlModesBitmap.unset_remote_latching = function(self)
  self.value = self.value & (~self.REMOTE_LATCHING & self.BASE_MASK)
end

LatchControlModesBitmap.is_remote_unlatching_set = function(self)
  return (self.value & self.REMOTE_UNLATCHING) ~= 0
end

LatchControlModesBitmap.set_remote_unlatching = function(self)
  if self.value ~= nil then
    self.value = self.value | self.REMOTE_UNLATCHING
  else
    self.value = self.REMOTE_UNLATCHING
  end
end

LatchControlModesBitmap.unset_remote_unlatching = function(self)
  self.value = self.value & (~self.REMOTE_UNLATCHING & self.BASE_MASK)
end

LatchControlModesBitmap.mask_methods = {
  is_remote_latching_set = LatchControlModesBitmap.is_remote_latching_set,
  set_remote_latching = LatchControlModesBitmap.set_remote_latching,
  unset_remote_latching = LatchControlModesBitmap.unset_remote_latching,
  is_remote_unlatching_set = LatchControlModesBitmap.is_remote_unlatching_set,
  set_remote_unlatching = LatchControlModesBitmap.set_remote_unlatching,
  unset_remote_unlatching = LatchControlModesBitmap.unset_remote_unlatching,
}

LatchControlModesBitmap.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(LatchControlModesBitmap, new_mt)

return LatchControlModesBitmap
