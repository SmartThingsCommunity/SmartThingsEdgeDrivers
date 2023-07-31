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
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Basic
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })
--- @type st.zwave.CommandClass.SwitchAll
local SwitchAll = (require "st.zwave.CommandClass.SwitchAll")({ version = 1 })
--- @type st.zwave.CommandClass.SwitchBinary
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version = 2 })
--- @type st.zwave.CommandClass.Association
local Association = (require "st.zwave.CommandClass.Association")({ version = 1 })

local INOVELLI_2_CHANNEL_SMART_PLUG_FINGERPRINTS = {
  {mfr = 0x015D, prod = 0x0221, model = 0x251C}, -- Show Home Outlet
  {mfr = 0x0312, prod = 0x0221, model = 0x251C}, -- Inovelli Outlet
  {mfr = 0x0312, prod = 0xB221, model = 0x251C}, -- Inovelli Outlet
  {mfr = 0x0312, prod = 0x0221, model = 0x611C}, -- Inovelli Outlet
  {mfr = 0x015D, prod = 0x0221, model = 0x611C}, -- Inovelli Outlet
  {mfr = 0x015D, prod = 0x6100, model = 0x6100}, -- Inovelli Outlet
  {mfr = 0x0312, prod = 0x6100, model = 0x6100}, -- Inovelli Outlet
  {mfr = 0x015D, prod = 0x2500, model = 0x2500}, -- Inovelli Outlet
}

local function can_handle_inovelli_2_channel_smart_plug(opts, driver, device, ...)
  for _, fingerprint in ipairs(INOVELLI_2_CHANNEL_SMART_PLUG_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      local subdriver = require("inovelli-2-channel-smart-plug")
      return true, subdriver
    end
  end
  return false
end

local inovelli_2_channel_smart_plug = {
  NAME = "Inovelli 2 channel smart plug",
  can_handle = can_handle_inovelli_2_channel_smart_plug
}

return inovelli_2_channel_smart_plug
