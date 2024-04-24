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
local colorTemperature_defaults = require "st.zigbee.defaults.colorTemperature_defaults"

local ColorControl = clusters.ColorControl

local WHITE_COLOR_TEMP_BULB_FINGERPRINTS = {
  ["DURAGREEN"] = {
    ["DG-CW-02"] = true,
    ["DG-CW-01"] = true,
    ["DG-CCT-01"] = true
  },
  ["Samsung Electronics"] = {
    ["ABL-LIGHT-Z-001"] = true,
    ["SAMSUNG-ITM-Z-001"] = true
  },
  ["Juno"] = {
    ["ABL-LIGHT-Z-001"] = true
  },
  ["AduroSmart Eria"] = {
    ["AD-ColorTemperature3001"] = true
  },
  ["Aurora"] = {
    ["TWBulb51AU"] = true,
    ["TWMPROZXBulb50AU"] = true,
    ["TWStrip50AU"] = true,
    ["TWGU10Bulb50AU"] = true,
    ["TWCLBulb50AU"] = true
  },
  ["CWD"] = {
    ["ZB.A806Ecct-A001"] = true,
    ["ZB.A806Bcct-A001"] = true,
    ["ZB.M350cct-A001"] = true
  },
  ["ETI"] = {
    ["Zigbee CCT Downlight"] = true
  },
  ["The Home Depot"] = {
    ["Ecosmart-ZBT-BR30-CCT-Bulb"] = true,
    ["Ecosmart-ZBT-A19-CCT-Bulb"] = true
  },
  ["IKEA of Sweden"] = {
    ["GUNNARP panel round"] = true,
    ["LEPTITER Recessed spot light"] = true,
    ["TRADFRI bulb E12 WS opal 600lm"] = true,
    ["TRADFRI bulb E14 WS 470lm"] = true,
    ["TRADFRI bulb E14 WS opal 600lm"] = true,
    ["TRADFRI bulb E26 WS clear 806lm"] = true,
    ["TRADFRI bulb E27 WS clear 806lm"] = true,
    ["TRADFRI bulb E26 WS opal 1000lm"] = true,
    ["TRADFRI bulb E27 WS opal 1000lm"] = true
  },
  ["Megaman"] = {
    ["Z3-ColorTemperature"] = true
  },
  ["innr"] = {
    ["RB 248 T"] = true,
    ["RB 278 T"] = true,
    ["RS 228 T"] = true
  },
  ["OSRAM"] = {
    ["LIGHTIFY BR Tunable White"] = true,
    ["LIGHTIFY RT Tunable White"] = true,
    ["Classic A60 TW"] = true,
    ["LIGHTIFY A19 Tunable White"] = true,
    ["Classic B40 TW - LIGHTIFY"] = true,
    ["LIGHTIFY Conv Under Cabinet TW"] = true,
    ["ColorstripRGBW"] = true,
    ["LIGHTIFY Edge-lit Flushmount TW"] = true,
    ["LIGHTIFY Surface TW"] = true,
    ["LIGHTIFY Under Cabinet TW"] = true,
    ["LIGHTIFY Edge-lit flushmount"] = true
  },
  ["LEDVANCE"] = {
    ["A19 TW 10 year"] = true,
    ["MR16 TW"] = true,
    ["BR30 TW"] = true,
    ["RT TW"] = true
  },
  ["Smarthome"] = {
    ["S111-202A"] = true
  },
  ["lk"] = {
    ["ZBT-CCTLight-GLS0108"] = true
  },
  ["MLI"] = {
    ["ZBT-ColorTemperature"] = true
  },
  ["sengled"] = {
    ["Z01-A19NAE26"] = true,
    ["Z01-A191AE26W"] = true,
    ["Z01-A60EAB22"] = true,
    ["Z01-A60EAE27"] = true
  },
  ["Third Reality, Inc"] = {
    ["3RSL011Z"] = true,
    ["3RSL012Z"] = true
  },
  ["Ajax Online"] = {
    ["CCT"] = true
  }
}

local function can_handle_white_color_temp_bulb(opts, driver, device)
  local can_handle = (WHITE_COLOR_TEMP_BULB_FINGERPRINTS[device:get_manufacturer()] or {})[device:get_model()]
  if can_handle then
    local subdriver = require("white-color-temp-bulb")
    return true, subdriver
  else
    return false
  end
end

local function set_color_temperature_handler(driver, device, cmd)
  colorTemperature_defaults.set_color_temperature(driver, device, cmd)

  device.thread:call_with_delay(1, function(d)
    device:send(ColorControl.attributes.ColorTemperatureMireds:read(device))
  end)
end

local white_color_temp_bulb = {
  NAME = "White Color Temp Bulb",
  capability_handlers = {
    [capabilities.colorTemperature.ID] = {
      [capabilities.colorTemperature.commands.setColorTemperature.NAME] = set_color_temperature_handler
    }
  },
  sub_drivers = {
    require("white-color-temp-bulb.duragreen"),
  },
  can_handle = can_handle_white_color_temp_bulb
}

return white_color_temp_bulb
