-- Copyright © 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local ThreeLevelAutoEnum = {}
local new_mt = UintABC.new_mt({NAME = "ThreeLevelAutoEnum", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.AUTO] = "AUTO",
    [self.LOW] = "LOW",
    [self.MEDIUM] = "MEDIUM",
    [self.HIGH] = "HIGH",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.AUTO  = 0x00
new_mt.__index.LOW  = 0x01
new_mt.__index.MEDIUM  = 0x02
new_mt.__index.HIGH  = 0x03

ThreeLevelAutoEnum.AUTO  = 0x00
ThreeLevelAutoEnum.LOW  = 0x01
ThreeLevelAutoEnum.MEDIUM  = 0x02
ThreeLevelAutoEnum.HIGH  = 0x03

ThreeLevelAutoEnum.augment_type = function(_cls, val)
  setmetatable(val, new_mt)
end

setmetatable(ThreeLevelAutoEnum, new_mt)


return ThreeLevelAutoEnum

