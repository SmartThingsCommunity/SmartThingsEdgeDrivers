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
local switch_defaults = require "st.zigbee.defaults.switch_defaults"

local OnOff = clusters.OnOff
local Level = clusters.Level
local ColorControl = clusters.ColorControl

local RGBW_BULB_FINGERPRINTS = {
  ["Samsung Electronics"] = {
    ["SAMSUNG-ITM-Z-002"] = true
  },
  ["Juno"] = {
    ["ABL-LIGHT-Z-201"] = true
  },
  ["AduroSmart Eria"] = {
    ["AD-RGBW3001"] = true
  },
  ["Aurora"] = {
    ["RGBCXStrip50AU"] = true,
    ["RGBGU10Bulb50AU"] = true,
    ["RGBBulb51AU"] = true
  },
  ["CWD"] = {
    ["ZB.A806Ergbw-A001"] = true,
    ["ZB.A806Brgbw-A001"] = true,
    ["ZB.M350rgbw-A001"] = true
  },
  ["innr"] = {
    ["RB 285 C"] = true,
    ["BY 285 C"] = true,
    ["RB 250 C"] = true,
    ["RS 230 C"] = true,
    ["AE 280 C"] = true
  },
  ["MLI"] = {
    ["ZBT-ExtendedColor"] = true
  },
  ["OSRAM"] = {
    ["LIGHTIFY Flex RGBW"] = true,
    ["Flex RGBW"] = true,
    ["LIGHTIFY A19 RGBW"] = true,
    ["LIGHTIFY BR RGBW"] = true,
    ["LIGHTIFY RT RGBW"] = true,
    ["LIGHTIFY FLEX OUTDOOR RGBW"] = true
  },
  ["LEDVANCE"] = {
    ["RT HO RGBW"] = true,
    ["A19 RGBW"] = true,
    ["FLEX Outdoor RGBW"] = true,
    ["FLEX RGBW"] = true,
    ["BR30 RGBW"] = true,
    ["RT RGBW"] = true,
    ["Outdoor Pathway RGBW"] = true,
    ["Flex RGBW Pro"] = true
  },
  ["LEEDARSON LIGHTING"] = {
    ["5ZB-A806ST-Q1G"] = true
  },
  ["sengled"] = {
    ["E11-N1EA"] = true,
    ["E12-N1E"] = true,
    ["E21-N1EA"] = true,
    ["E1G-G8E"] = true,
    ["E11-U3E"] = true,
    ["E11-U2E"] = true,
    ["E1F-N5E"] = true,
    ["E23-N13"] = true
  },
  ["Neuhaus Lighting Group"] = {
    ["ZBT-ExtendedColor"] = true
  },
  ["Ajaxonline"] = {
    ["AJ-RGBCCT 5 in 1"] = true
  },
  ["Ajax online Ltd"] = {
    ["AJ_ZB30_GU10"] = true
  }
}

local function can_handle_rgbw_bulb(opts, driver, device)
  local can_handle = (RGBW_BULB_FINGERPRINTS[device:get_manufacturer()] or {})[device:get_model()]
  if can_handle then
    local subdriver = require("rgbw-bulb")
    return true, subdriver
  else
    return false
  end
end

local function do_refresh(driver, device)
  local attributes = {
    OnOff.attributes.OnOff,
    Level.attributes.CurrentLevel,
    ColorControl.attributes.ColorTemperatureMireds,
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

-- This is only intended to ever happen once, before the device has a color temp
local function do_added(driver, device)
  device:send(ColorControl.commands.MoveToColorTemperature(device, 200, 0x0000))
end

local function set_color_temperature_handler(driver, device, cmd)
  switch_defaults.on(driver, device, cmd)
  local temp_in_mired = math.floor(1000000 / cmd.args.temperature)
  device:send(ColorControl.commands.MoveToColorTemperature(device, temp_in_mired, 0x0000))

  device.thread:call_with_delay(1, function(d)
    device:send(ColorControl.attributes.ColorTemperatureMireds:read(device))
  end)
end

local rgbw_bulb = {
  NAME = "RGBW Bulb",
  capability_handlers = {
    [capabilities.colorTemperature.ID] = {
      [capabilities.colorTemperature.commands.setColorTemperature.NAME] = set_color_temperature_handler
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    }
  },
  lifecycle_handlers = {
    doConfigure = do_configure,
    added = do_added
  },
  can_handle = can_handle_rgbw_bulb
}

return rgbw_bulb
