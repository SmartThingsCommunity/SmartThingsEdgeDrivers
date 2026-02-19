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

local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local LockCluster = clusters.DoorLock
local LockCredentials = capabilities.lockCredentials
local LockUsers = capabilities.lockUsers

local YALE_FINGERPRINT_MAX_CODES = 0x1E

local handle_max_codes = function(driver, device, value)
  device:emit_event(LockCredentials.pinUsersSupported(YALE_FINGERPRINT_MAX_CODES))
  device:emit_event(LockUsers.totalUsersSupported(YALE_FINGERPRINT_MAX_CODES))
end

local yale_fingerprint_lock_driver = {
  NAME = "YALE Fingerprint Lock",
  zigbee_handlers = {
    attr = {
      [LockCluster.ID] = {
        [LockCluster.attributes.NumberOfPINUsersSupported.ID] = handle_max_codes
      }
    }
  },
  can_handle =  require("using-new-capabilities.yale-fingerprint-lock.can_handle")
}

return yale_fingerprint_lock_driver
