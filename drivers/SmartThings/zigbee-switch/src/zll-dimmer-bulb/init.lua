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

local ZLL_DIMMER_BULB_FINGERPRINTS = {
  ["AduroSmart Eria"] = {
    ["ZLL-DimmableLight"] = true,
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
    ["JORMLIEN door WS 40x80"] = true
  },
  ["Eaton"] = {
    ["Halo_RL5601"] = true
  },
  ["Megaman"] = {
    ["ZLL-DimmableLight"] = true,
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
    ["RB 148 T"] = true
  },
  ["Leviton"] = {
    ["DG3HL"] = true,
    ["DG6HD"] = true
  },
  ["OSRAM"] = {
    ["Classic A60 W clear"] = true,
    ["Classic A60 W clear - LIGHTIFY"] = true,
    ["CLA60 OFD OSRAM"] = true,
    ["Classic B40 TW - LIGHTIFY"] = true,
    ["CLA60 TW OSRAM"] = true
  },
  ["Philips"] = {
    ["LWB006"] = true,
    ["LWB007"] = true,
    ["LWB010"] = true,
    ["LWB014"] = true,
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
    ["E14-U43"] = true
  },
  ["Ubec"] = {
    ["BBB65L-HY"] = true
  }
}

local REFRESH_ATTRIBUTES = {
  [capabilities.colorControl] = {
    ColorControl.attributes.CurrentHue,
    ColorControl.attributes.CurrentSaturation
  }
}

local function can_handle_zll_dimmer_bulb(opts, driver, device)
  return (ZLL_DIMMER_BULB_FINGERPRINTS[device:get_manufacturer()] or {})[device:get_model()] or false
end

local function do_refresh(driver, device)
  device:refresh()

  for capability, attributes in pairs(REFRESH_ATTRIBUTES) do
    if device:supports_capability(capability) then
      for _,attr in ipairs(attributes) do
        device:send(attr:read(device))
      end
    end
  end
end

local function handle_switch_on(driver, device, cmd)
  device:send(OnOff.commands.On(device))

  device.thread:call_with_delay(2, function(d)
    do_refresh(driver, device)
  end)
end

local function handle_switch_off(driver, device, cmd)
  device:send(OnOff.commands.Off(device))

  device.thread:call_with_delay(2, function(d)
    do_refresh(driver, device)
  end)
end

local function handle_set_level(driver, device, cmd)
  local level = math.floor(cmd.args.level / 100.0 * 254)
  device:send(Level.commands.MoveToLevelWithOnOff(device, level, cmd.args.rate or 0xFFFF))

  device.thread:call_with_delay(2, function(d)
    do_refresh(driver, device)
  end)
end

local function handle_set_color_temperature(driver, device, cmd)
  local temp_in_mired = math.floor(1000000 / cmd.args.temperature)
  device:send(OnOff.commands.On(device))
  device:send(ColorControl.commands.MoveToColorTemperature(device, temp_in_mired, 0x0000))

  local function query_device()
    do_refresh(driver, device)
  end
  device.thread:call_with_delay(2, query_device)
end


local zll_dimmer_bulb = {
  NAME = "ZLL Dimmer Bulb",
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
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    }
  },
  can_handle = can_handle_zll_dimmer_bulb
}

return zll_dimmer_bulb
