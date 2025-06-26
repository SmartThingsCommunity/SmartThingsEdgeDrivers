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

local capabilities = require "st.capabilities"

local custom_capabilities = {
    ai_mode = capabilities["stse.aiMode"],
    auto_inflation = capabilities["stse.autoInflation"],
    strong_exp_mode = capabilities["stse.strongExpMode"],
    left_control = capabilities["stse.leftControl"],
    right_control = capabilities["stse.rightControl"],
    yoga = capabilities["stse.yoga"],
    mattressHardness = capabilities["stse.mattressHardness"]
}

return custom_capabilities
