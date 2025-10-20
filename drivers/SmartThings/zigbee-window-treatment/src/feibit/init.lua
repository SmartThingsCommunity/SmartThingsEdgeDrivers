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
local zcl_clusters = require "st.zigbee.zcl.clusters"
local window_shade_utils = require "window_shade_utils"
local window_shade_defaults = require "st.zigbee.defaults.windowShade_defaults"
local device_management = require "st.zigbee.device_management"
local Level = zcl_clusters.Level

local ZIGBEE_WINDOW_SHADE_FINGERPRINTS = {
    { mfr = "Feibit Co.Ltd", model = "FTB56-ZT218AK1.6" },
    { mfr = "Feibit Co.Ltd", model = "FTB56-ZT218AK1.8" },
}

local is_zigbee_window_shade = function(opts, driver, device)
  for _, fingerprint in ipairs(ZIGBEE_WINDOW_SHADE_FINGERPRINTS) do
      if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
          return true
      end
  end

  return false
end

local function set_shade_level(device, value, component)
  local level = math.floor(value / 100.0 * 254)
  device:send_to_component(component, Level.server.commands.MoveToLevelWithOnOff(device, level))
end

local function window_shade_level_cmd_handler(driver, device, command)
  set_shade_level(device, command.args.shadeLevel, command.component)
end

local function level_attr_handler(driver, device, value, zb_rx)
  local current_level = math.floor(value.value / 100 * 254)
  value.value = current_level
  window_shade_defaults.default_current_lift_percentage_handler(driver, device, value, zb_rx)
end

local function window_shade_preset_cmd(driver, device, command)
  local level = window_shade_utils.get_preset_level(device, command.component)
  set_shade_level(device, level, command.component)
end

local do_refresh = function(self, device)
  device:send(Level.attributes.CurrentLevel:read(device))
end

local do_configure = function(self, device)
  device:send(device_management.build_bind_request(device, Level.ID, self.environment_info.hub_zigbee_eui))
  device:send(Level.attributes.CurrentLevel:configure_reporting(device, 1, 3600, 1))
end

local feibit_handler = {
  NAME = "Feibit Device Handler",
  capability_handlers = {
    [capabilities.windowShadeLevel.ID] = {
      [capabilities.windowShadeLevel.commands.setShadeLevel.NAME] = window_shade_level_cmd_handler
    },
    [capabilities.windowShadePreset.ID] = {
      [capabilities.windowShadePreset.commands.presetPosition.NAME] = window_shade_preset_cmd
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    }
  },
  zigbee_handlers = {
    attr = {
      [Level.ID] = {
        [Level.attributes.CurrentLevel.ID] = level_attr_handler
      }
    }
  },
  lifecycle_handlers = {
    doConfigure = do_configure,
  },
  can_handle = is_zigbee_window_shade,
}

return feibit_handler
