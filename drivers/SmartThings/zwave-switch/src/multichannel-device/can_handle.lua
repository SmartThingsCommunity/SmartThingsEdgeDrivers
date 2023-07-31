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
local cc = require "st.zwave.CommandClass"
local capabilities = require "st.capabilities"
local st_device = require "st.device"
local MultiChannel = (require "st.zwave.CommandClass.MultiChannel")({ version = 3 })
local utils = require "st.utils"

local function can_handle_multichannel_device (opts, driver, device, ...)
  if device:supports_capability(capabilities.zwMultichannel) then
    local subdriver = require("multichannel-device")
    return true, subdriver
  else
    return false
  end
end

local multichannel_device = {
  NAME = "Z-Wave Device Multichannel",
  can_handle = can_handle_multichannel_device
}

return multichannel_device
