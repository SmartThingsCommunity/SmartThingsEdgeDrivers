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
local ColorControl = clusters.ColorControl

local RGB_BULB_FINGERPRINTS = {
  ["OSRAM"] = {
    ["Gardenspot RGB"] = true,
    ["LIGHTIFY Gardenspot RGB"] = true
  },
  ["LEDVANCE"] = {
    ["Outdoor Accent RGB"] = true
  }
}

local function can_handle_rgb_bulb(opts, driver, device)
  local can_handle = (RGB_BULB_FINGERPRINTS[device:get_manufacturer()] or {})[device:get_model()]
  if can_handle then
    local subdriver = require("rgb-bulb")
    return true, subdriver
  else
    return false
  end
end

local function do_refresh(driver, device)
  local attributes = {
  OnOff.attributes.OnOff,
  Level.attributes.CurrentLevel,
  ColorControl.attributes.CurrentHue,
  ColorControl.attributes.CurrentSaturation
  }
  for _, attribute in pairs(attributes) do
    device:send(attribute:read(device))
  end
end

local function do_configure(driver, device)
  device:configure()
  do_refresh(driver, device)
end

local rgb_bulb = {
  NAME = "RGB Bulb",
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    }
  },
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  can_handle = can_handle_rgb_bulb
}

return rgb_bulb
