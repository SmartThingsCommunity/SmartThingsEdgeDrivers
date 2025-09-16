-- Copyright 2025 SmartThings
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

local defaults = require "st.zigbee.defaults"
local capabilities = require "st.capabilities"

local is_contact_sensor = function(opts, driver, device)
  if device:supports_capability(capabilities.contactSensor) then
    return true
  end
end

local generic_contact_sensor = {
  NAME = "Generic Contact Sensor",
  supported_capabilities = {
    capabilities.contactSensor
  },
  can_handle = is_contact_sensor,
}
defaults.register_for_default_handlers(generic_contact_sensor, generic_contact_sensor.supported_capabilities)
return generic_contact_sensor