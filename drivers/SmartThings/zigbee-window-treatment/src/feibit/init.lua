-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local window_shade_utils = require "window_shade_utils"
local window_shade_defaults = require "st.zigbee.defaults.windowShade_defaults"
local device_management = require "st.zigbee.device_management"
local Level = zcl_clusters.Level



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
  device:refresh()
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
  can_handle = require("feibit.can_handle"),
}

return feibit_handler
