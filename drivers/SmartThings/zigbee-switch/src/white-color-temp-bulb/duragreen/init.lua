-- Copyright 2023 SmartThings
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

local function handle_set_level(driver, device, cmd)
  local level = math.floor(cmd.args.level/100.0 * 254)
  local transtition_time = cmd.args.rate or 0xFFFF
  local command = Level.server.commands.MoveToLevelWithOnOff(device, level, transtition_time)

  command.body.zcl_body.options_mask = nil
  command.body.zcl_body.options_override = nil
  device:send(command)
end

local duragreen_color_temp_bulb = {
  NAME = "DuraGreen Color Temp Bulb",
  capability_handlers = {
    [capabilities.switchLevel.ID] = {
      [capabilities.switchLevel.commands.setLevel.NAME] = handle_set_level
    }
  },
  can_handle = require("white-color-temp-bulb.duragreen.can_handle")
}

return duragreen_color_temp_bulb
