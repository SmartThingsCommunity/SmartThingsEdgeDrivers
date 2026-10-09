-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local PowerConfiguration = zcl_clusters.PowerConfiguration
local OnOff = zcl_clusters.OnOff
local WindowCovering = zcl_clusters.WindowCovering


local INVERT_CLUSTER = 0xFC00
local INVERT_CLUSTER_ATTRIBUTE = 0x0000
local PREV_TIME = "shadeLevelCmdTime"


local function invert_preference_handler(device)
  local window_level = device:get_latest_state("main", capabilities.windowShadeLevel.ID, capabilities.windowShadeLevel.shadeLevel.NAME) or 0
  local window_shade = capabilities.windowShade.windowShade
  device:emit_event(window_level == 100 and window_shade.closed() or window_shade.open())
  device:emit_event(capabilities.windowShadeLevel.shadeLevel(100 - window_level))
  -- if invert is false then normal case handler or reverse case handler
  local invert_value = device.preferences.invert
  local invert_cluster_cmd = cluster_base.write_manufacturer_specific_attribute(device,
                                                                                INVERT_CLUSTER,
                                                                                INVERT_CLUSTER_ATTRIBUTE,
                                                                                0x0000, data_types.Boolean,
                                                                                invert_value)
  device:send(invert_cluster_cmd)
end

local function info_changed(driver, device, event, args)
  if device.preferences ~= nil and device.preferences.invert ~= args.old_st_store.preferences.invert then
    invert_preference_handler(device)
  end
end

local function current_position_attr_handler(driver, device, value, zb_rx)
  local level = value.value
  local window_shade = capabilities.windowShade.windowShade
  device:emit_event(capabilities.windowShadeLevel.shadeLevel(level))
  if level == 0 or level == 100 then
    device:emit_event(level == 0 and window_shade.closed() or window_shade.open())
  elseif level > 0 and level < 100 then
    device:emit_event(window_shade.partially_open())
  end
end

local function on_off_attr_handler(driver, device, value, zb_rx)
  local window_shade = capabilities.windowShade.windowShade
  local shade_level = capabilities.windowShadeLevel.shadeLevel
  device:emit_event(value.value == false and window_shade.closed() or window_shade.open())
  device:emit_event(value.value == false and shade_level(0) or shade_level(100))
end

local function build_window_shade_cmd(cmd_type)
  return function(driver, device, command)
    device:send_to_component(command.component, cmd_type(device))
  end
end

local function window_shade_level_cmd(driver, device, command)
  local time = os.time()
  local prev_time = device:get_field(PREV_TIME) or 0
  local level = 100 - command.args.shadeLevel
  if time - prev_time > 1 then
    device:send_to_component(command.component, WindowCovering.server.commands.GoToLiftPercentage(device, level))
  end
  device:set_field(PREV_TIME, time)
end

local do_refresh = function(self, device)
  device:send(OnOff.attributes.OnOff:read(device))
  device:send(WindowCovering.attributes.CurrentPositionLiftPercentage:read(device))
  device:send(PowerConfiguration.attributes.BatteryVoltage:read(device))
  local invert_cluster_read = cluster_base.read_manufacturer_specific_attribute(device, INVERT_CLUSTER, INVERT_CLUSTER_ATTRIBUTE, 0x0000)
  device:send(invert_cluster_read)
end

local rooms_beautiful_handler = {
  NAME = "Rooms Beautiful Device Handler",
  capability_handlers = {
    [capabilities.windowShadeLevel.ID] = {
      [capabilities.windowShadeLevel.commands.setShadeLevel.NAME] = window_shade_level_cmd
    },
    [capabilities.windowShade.ID] = {
      [capabilities.windowShade.commands.open.NAME] = build_window_shade_cmd(OnOff.server.commands.On),
      [capabilities.windowShade.commands.close.NAME] = build_window_shade_cmd(OnOff.server.commands.Off),
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    }
  },
  zigbee_handlers = {
    attr = {
      [OnOff.ID] = {
        [OnOff.attributes.OnOff.ID] = on_off_attr_handler
      },
      [WindowCovering.ID] = {
        [WindowCovering.attributes.CurrentPositionLiftPercentage.ID] = current_position_attr_handler
      }
    }
  },
  lifecycle_handlers = {
    init = battery_defaults.build_linear_voltage_init(2.5, 3.0),
    infoChanged = info_changed
  },
  can_handle = require("rooms-beautiful.can_handle"),
}

return rooms_beautiful_handler
