-- Copyright 2024 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local UintABC = require "st.matter.data_types.base_defs.UintABC"
local data_types = require("st.matter.data_types")

local mt = UintABC.new_mt({ NAME = "Uint64", ID = 0x07, SUBTYPES = { "Uint8", "Uint16", "Uint32" } }, 8)

mt.__index.check_if_valid = function(self, int_val)
    if math.type(int_val) ~= "integer" then
      error(string.format("%s value must be an integer", self.NAME), 2)
    end
end


local Uint64 = {}
setmetatable(Uint64, mt)
data_types["Uint64"] = Uint64

return data_types
