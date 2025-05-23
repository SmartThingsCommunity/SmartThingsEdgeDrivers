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

local clusters = require "st.matter.clusters"
local common_utils = require "common-utils"
local device_lib = require "st.device"
local log = require "log"
local modular_profiles_utils = require "modular-profiles-utils"

-------------------------------------------------------------------------------------
-- Modular Profile sub-driver
-------------------------------------------------------------------------------------

local function is_modular_profile_device(opts, driver, device)
  if device.network_type == device_lib.NETWORK_TYPE_MATTER and
     common_utils.supports_modular_profile(device) and
     not common_utils.detect_bridge(device) then
    log.info("Using Modular Profile sub-driver")
    return true
  end
  return false
end

local function do_configure(driver, device)
  if device.network_type == device_lib.NETWORK_TYPE_MATTER then
    modular_profiles_utils.match_profile(driver, device)
  end
end

local function driver_switched(driver, device)
  if device.network_type == device_lib.NETWORK_TYPE_MATTER then
    modular_profiles_utils.match_profile(driver, device)
  end
end

local modular_profile_handler = {
  NAME = "Modular Profile Handler",
  lifecycle_handlers = {
    doConfigure = do_configure,
    driverSwitched = driver_switched
  },
  matter_handlers = {
    attr = {
      [clusters.PowerSource.ID] = {
        [clusters.PowerSource.attributes.AttributeList.ID] = modular_profiles_utils.power_source_attribute_list_handler
      }
    }
  },
  can_handle = is_modular_profile_device
}

return modular_profile_handler
