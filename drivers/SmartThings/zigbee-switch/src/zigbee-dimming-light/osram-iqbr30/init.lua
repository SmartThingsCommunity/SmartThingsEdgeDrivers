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

local OnOff = clusters.OnOff
local Level = clusters.Level

local SwitchLevel = capabilities.switchLevel

local function set_switch_level_handler(driver, device, cmd)
  local level = math.floor(cmd.args.level / 100.0 * 254)

  device:send(Level.server.commands.MoveToLevelWithOnOff(device, level, cmd.args.rate or 0xFFFF))
  if(level > 0) then
    device:send(OnOff.server.commands.On(device))
  end
end

local osram_iqbr30 = {
  NAME = "Zigbee Osram iQBR30 Dimmer",
  capability_handlers = {
    [SwitchLevel.ID] = {
      [SwitchLevel.commands.setLevel.NAME] = set_switch_level_handler
    }
  },
  can_handle = require("zigbee-dimming-light.osram-iqbr30.can_handle"),
}

return osram_iqbr30
