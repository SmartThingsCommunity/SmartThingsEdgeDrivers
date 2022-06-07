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
local clusters = require "st.zigbee.zcl.clusters"

local Level = clusters.Level

local SwitchLevel = capabilities.switchLevel

local ZLL_DIMMER_FINGERPRINTS = {
  {mfr = "Leviton", model = "DL6HD"},   -- Leviton Dimmer Switch
  {mfr = "Leviton", model = "DL3HL"},   -- Leviton Lumina RF Plug-In Dimmer
  {mfr = "Leviton", model = "DL1KD"},   -- Leviton Lumina RF Dimmer Switch
  {mfr = "Leviton", model = "ZSD07"},   -- Leviton Lumina RF 0-10V Dimming Wall Switch
  {mfr = "MRVL", model = "MZ100"},
  {mfr = "CREE", model = "Connected A-19 60W Equivalent"}
}

local function can_handle_zll_dimmer(opts, driver, device)
  for _, fingerprint in ipairs(ZLL_DIMMER_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function set_switch_level_handler(driver, device, cmd)
  local level = math.floor(cmd.args.level / 100.0 * 254)

  device:send(Level.server.commands.MoveToLevelWithOnOff(device, level, cmd.args.rate or 0xFFFF))
  device:refresh()
end

local zll_dimmer = {
  NAME = "Zigbee Leviton Dimmer",
  capability_handlers = {
    [SwitchLevel.ID] = {
      [SwitchLevel.commands.setLevel.NAME] = set_switch_level_handler
    }
  },
  can_handle = can_handle_zll_dimmer
}

return zll_dimmer
