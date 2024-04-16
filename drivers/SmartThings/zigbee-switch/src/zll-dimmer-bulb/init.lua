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

local OnOff = clusters.OnOff
local Level = clusters.Level

local ZLL_DIMMER_BULB_FINGERPRINTS = {
  ["AduroSmart Eria"] = {
    ["ZLL-DimmableLight"] = true,
    ["ZLL-ExtendedColor"] = true,
    ["ZLL-ColorTemperature"] = true
  },
  ["IKEA of Sweden"] = {
    ["TRADFRI bulb E26 opal 1000lm"] = true,
    ["TRADFRI bulb E12 W op/ch 400lm"] = true,
    ["TRADFRI bulb E17 W op/ch 400lm"] = true,
    ["TRADFRI bulb GU10 W 400lm"] = true,
    ["TRADFRI bulb E27 W opal 1000lm"] = true,
    ["TRADFRI bulb E26 W opal 1000lm"] = true,
    ["TRADFRI bulb E14 W op/ch 400lm"] = true,
    ["TRADFRI transformer 10W"] = true,
    ["TRADFRI Driver 10W"] = true,
    ["TRADFRI transformer 30W"] = true,
    ["TRADFRI Driver 30W"] = true,
    ["TRADFRI bulb E26 WS clear 950lm"] = true,
    ["TRADFRI bulb GU10 WS 400lm"] = true,
    ["TRADFRI bulb E12 WS opal 400lm"] = true,
    ["TRADFRI bulb E26 WS opal 980lm"] = true,
    ["TRADFRI bulb E27 WS clear 950lm"] = true,
    ["TRADFRI bulb E14 WS opal 400lm"] = true,
    ["TRADFRI bulb E27 WS opal 980lm"] = true,
    ["FLOALT panel WS 30x30"] = true,
    ["FLOALT panel WS 30x90"] = true,
    ["FLOALT panel WS 60x60"] = true,
    ["SURTE door WS 38x64"] = true,
    ["JORMLIEN door WS 40x80"] = true,
    ["TRADFRI bulb E27 CWS opal 600lm"] = true,
    ["TRADFRI bulb E26 CWS opal 600lm"] = true
  },
  ["Eaton"] = {
    ["Halo_RL5601"] = true
  },
  ["Megaman"] = {
    ["ZLL-DimmableLight"] = true,
    ["ZLL-ExtendedColor"] = true
  },
  ["MEGAMAN"] = {
    ["BSZTM002"] = true,
    ["BSZTM003"] = true
  },
  ["innr"] = {
    ["RS 125"] = true,
    ["RB 165"] = true,
    ["RB 175 W"] = true,
    ["RB 145"] = true,
    ["RS 128 T"] = true,
    ["RB 178 T"] = true,
    ["RB 148 T"] = true,
    ["RB 185 C"] = true,
    ["FL 130 C"] = true,
    ["OFL 120 C"] = true,
    ["OFL 140 C"] = true,
    ["OSL 130 C"] = true
  },
  ["Leviton"] = {
    ["DG3HL"] = true,
    ["DG6HD"] = true
  },
  ["OSRAM"] = {
    ["Classic A60 W clear"] = true,
    ["Classic A60 W clear - LIGHTIFY"] = true,
    ["CLA60 OFD OSRAM"] = true,
    ["Classic A60 RGBW"] = true,
    ["PAR 16 50 RGBW - LIGHTIFY"] = true,
    ["CLA60 RGBW OSRAM"] = true,
    ["Flex RGBW"] = true,
    ["Gardenpole RGBW-Lightify"] = true,
    ["LIGHTIFY Outdoor Flex RGBW"] = true,
    ["LIGHTIFY Indoor Flex RGBW"] = true,
    ["Classic B40 TW - LIGHTIFY"] = true,
    ["CLA60 TW OSRAM"] = true
  },
  ["Philips"] = {
    ["LWB006"] = true,
    ["LWB007"] = true,
    ["LWB010"] = true,
    ["LWB014"] = true,
    ["LCT001"] = true,
    ["LCT002"] = true,
    ["LCT003"] = true,
    ["LCT007"] = true,
    ["LCT010"] = true,
    ["LCT011"] = true,
    ["LCT012"] = true,
    ["LCT014"] = true,
    ["LCT015"] = true,
    ["LCT016"] = true,
    ["LST001"] = true,
    ["LST002"] = true,
    ["LTW001"] = true,
    ["LTW004"] = true,
    ["LTW010"] = true,
    ["LTW011"] = true,
    ["LTW012"] = true,
    ["LTW013"] = true,
    ["LTW014"] = true,
    ["LTW015"] = true
  },
  ["sengled"] = {
    ["E14-U43"] = true,
    ["E13-N11"] = true
  },
  ["GLEDOPTO"] = {
    ["GL-C-008"] = true,
    ["GL-B-001Z"] = true
  },
  ["Ubec"] = {
    ["BBB65L-HY"] = true
  }
}

local function can_handle_zll_dimmer_bulb(opts, driver, device)
  local can_handle = (ZLL_DIMMER_BULB_FINGERPRINTS[device:get_manufacturer()] or {})[device:get_model()]
  if can_handle then
    local subdriver = require("zll-dimmer-bulb")
    return true, subdriver
  else
    return false
  end
end

local function do_configure(driver, device)
  device:configure()
end

local function device_added(driver, device)
  device:refresh()
end

local function handle_switch_on(driver, device, cmd)
  device:send(OnOff.commands.On(device))

  device.thread:call_with_delay(2, function(d)
    device:refresh()
  end)
end

local function handle_switch_off(driver, device, cmd)
  device:send(OnOff.commands.Off(device))

  device.thread:call_with_delay(2, function(d)
    device:refresh()
  end)
end

local function handle_set_level(driver, device, cmd)
  local level = math.floor(cmd.args.level / 100.0 * 254)
  device:send(Level.commands.MoveToLevelWithOnOff(device, level, cmd.args.rate or 0xFFFF))

  device.thread:call_with_delay(2, function(d)
    device:refresh()
  end)
end

local function handle_set_color_temperature(driver, device, cmd)
  colorTemperature_defaults.set_color_temperature(driver, device, cmd)

  local function query_device()
    device:refresh()
  end
  device.thread:call_with_delay(2, query_device)
end

local zll_dimmer_bulb = {
  NAME = "ZLL Dimmer Bulb",
  lifecycle_handlers = {
    doConfigure = do_configure,
    added = device_added
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = handle_switch_on,
      [capabilities.switch.commands.off.NAME] = handle_switch_off
    },
    [capabilities.switchLevel.ID] = {
      [capabilities.switchLevel.commands.setLevel.NAME] = handle_set_level
    },
    [capabilities.colorTemperature.ID] = {
      [capabilities.colorTemperature.commands.setColorTemperature.NAME] = handle_set_color_temperature
    }
  },
  sub_drivers = {
    require("zll-dimmer-bulb/ikea-xy-color-bulb")
  },
  can_handle = can_handle_zll_dimmer_bulb
}

return zll_dimmer_bulb
