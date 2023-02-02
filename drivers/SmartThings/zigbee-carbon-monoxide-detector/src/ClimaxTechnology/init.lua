-- Copyright 2022 SmartThings
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

local CLIMAX_TECHNOLOGY_CARBON_MONOXIDE_FINGERPRINTS = {
    { mfr = "ClimaxTechnology", model = "CO_00.00.00.22TC" },
    { mfr = "ClimaxTechnology", model = "CO_00.00.00.15TC" }
}

local is_climax_technology_carbon_monoxide = function(opts, driver, device)
    for _, fingerprint in ipairs(CLIMAX_TECHNOLOGY_CARBON_MONOXIDE_FINGERPRINTS) do
        if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
            return true
        end
    end

    return false
end

local device_added = function(self, device)
    -- device:emit_event(capabilities.battery.battery(100))
end

local climax_technology_carbon_monoxide = {
    NAME = "ClimaxTechnology Carbon Monoxide",
    lifecycle_handlers = {
        added = device_added
    },
    can_handle = is_climax_technology_carbon_monoxide
}

return climax_technology_carbon_monoxide
