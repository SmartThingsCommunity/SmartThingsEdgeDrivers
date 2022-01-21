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

local Switch = capabilities.switch
local SwitchLevel = capabilities.switchLevel
local ColorTemperature = capabilities.colorTemperature
local Refresh = capabilities.refresh

local ZLL_BULB_FINGERPRINTS = {
  {mfr = "Eaton", model = "Halo_RL5601"},
  {mfr = "IKEA of Sweden", model = "TRADFRI bulb E26 WS clear 950lm"},
  {mfr = "IKEA of Sweden", model = "TRADFRI bulb GU10 WS 400lm"},
  {mfr = "IKEA of Sweden", model = "TRADFRI bulb E12 WS opal 400lm"},
  {mfr = "IKEA of Sweden", model = "TRADFRI bulb E26 WS opal 980lm"},
  {mfr = "IKEA of Sweden", model = "TRADFRI bulb E27 WS clear 950lm"},
  {mfr = "IKEA of Sweden", model = "TRADFRI bulb E14 WS opal 400lm"},
  {mfr = "IKEA of Sweden", model = "TRADFRI bulb E27 WS opal 980lm"},
  {mfr = "innr", model = "RS 128 T"},
  {mfr = "innr", model = "RB 178 T"},
  {mfr = "innr", model = "RB 148 T"}
}

local function can_handle_zll_color_temp_bulb(opts, driver, device)
  for _, fingerprint in ipairs(ZLL_BULB_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function do_refresh(driver, device, cmd)
  local supported_attributes = {
    OnOff.attributes.OnOff,
    Level.attributes.CurrentLevel,
    ColorControl.attributes.ColorTemperatureMireds
  }

  for _,attribute in pairs(supported_attributes) do
    device:send(attribute:read(device))
  end
end

local function set_switch_on_handler(driver, device, cmd)
  device:send(OnOff.commands.On(device))

  device.thread:call_with_delay(1, function() device:send(OnOff.attributes.OnOff:read(device)) end)
end

local function set_switch_off_handler(driver, device, cmd)
  device:send(OnOff.commands.Off(device))

  device.thread:call_with_delay(1, function() device:send(OnOff.attributes.OnOff:read(device)) end)
end

local function set_switch_level_handler(driver, device, cmd)
  local level = math.floor(cmd.args.level / 100.0 * 254)

  device:send(Level.commands.MoveToLevelWithOnOff(device, level, cmd.args.rate or 0xFFFF))

  local function query_device()
    device:send(OnOff.attributes.OnOff:read(device))
    device:send(Level.attributes.CurrentLevel:read(device))
  end
  device.thread:call_with_delay(1, query_device)
end

local function set_color_temperature_handler(driver, device, cmd)
  local temp_in_mired = math.floor(1000000 / cmd.args.temperature)
  device:send(OnOff.commands.On(device))
  device:send(ColorControl.commands.MoveToColorTemperature(device, temp_in_mired, 0x0000))

  local function query_device()
    device:send(OnOff.attributes.OnOff:read(device))
    device:send(ColorControl.attributes.ColorTemperatureMireds:read(device))
  end
  device.thread:call_with_delay(1, query_device)
end

local zll_color_temp_bulb = {
  NAME = "ZLL Color Temperature Bulb",
  capability_handlers = {
    [Switch.ID] = {
      [Switch.commands.on.NAME] = set_switch_on_handler,
      [Switch.commands.off.NAME] = set_switch_off_handler
    },
    [SwitchLevel.ID] = {
      [SwitchLevel.commands.setLevel.NAME] = set_switch_level_handler
    },
    [ColorTemperature.ID] = {
      [ColorTemperature.commands.setColorTemperature.NAME] = set_color_temperature_handler
    },
    [Refresh.ID] = {
      [Refresh.commands.refresh.NAME] = do_refresh,
    }
  },
  can_handle = can_handle_zll_color_temp_bulb
}

return zll_color_temp_bulb
