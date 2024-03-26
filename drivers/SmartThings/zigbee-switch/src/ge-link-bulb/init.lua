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

local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"

local Level = clusters.Level

local GE_LINK_BULB_FINGERPRINTS = {
  ["GE_Appliances"] = {
    ["ZLL Light"] = true,
  },
  ["GE"] = {
    ["Daylight"] = true,
    ["SoftWhite"] = true
  }
}

local function can_handle_ge_link_bulb(opts, driver, device)
  local can_handle = (GE_LINK_BULB_FINGERPRINTS[device:get_manufacturer()] or {})[device:get_model()]
  if can_handle then
    local subdriver = require("ge-link-bulb")
    return true, subdriver
  else
    return false
  end
end

local function info_changed(driver, device, event, args)
  local command
  local new_dim_onoff_value = tonumber(device.preferences.dimOnOff)
  local new_dim_rate_value = tonumber(device.preferences.dimRate)

  if device.preferences then
    if device.preferences.dimOnOff ~= args.old_st_store.preferences.dimOnOff then
      if new_dim_onoff_value == 0 then
        command = Level.attributes.OnOffTransitionTime:write(device, 0)
      else
        command = Level.attributes.OnOffTransitionTime:write(device, new_dim_rate_value)
      end
    elseif device.preferences.dimRate ~= args.old_st_store.preferences.dimRate and tonumber(device.preferences.dimOnOff) == 1 then
      command = Level.attributes.OnOffTransitionTime:write(device, new_dim_rate_value)
    end
  end

  if command then
    device:send(command)
  end
end

local function set_level_handler(driver, device, cmd)
  local level = math.floor(cmd.args.level / 100.0 * 254)
  local dimming_rate = tonumber(device.preferences.dimRate) or 0
  local query_delay = math.floor(dimming_rate / 10 + 0.5)

  device:send(Level.commands.MoveToLevelWithOnOff(device, level, dimming_rate == 0 and 0xFFFF or dimming_rate))

  device.thread:call_with_delay(query_delay, function(d)
    device:refresh()
  end)
end

local ge_link_bulb = {
  NAME = "GE Link Bulb",
  lifecycle_handlers = {
    infoChanged = info_changed
  },
  capability_handlers = {
    [capabilities.switchLevel.ID] = {
      [capabilities.switchLevel.commands.setLevel.NAME] = set_level_handler
    }
  },
  can_handle = can_handle_ge_link_bulb
}

return ge_link_bulb
