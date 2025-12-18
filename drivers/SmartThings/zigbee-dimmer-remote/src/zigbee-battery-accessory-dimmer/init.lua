-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0



local zcl_clusters = require "st.zigbee.zcl.clusters"
local OnOff = zcl_clusters.OnOff

local capabilities = require "st.capabilities"
local Switch = capabilities.switch
local SwitchLevel = capabilities.switchLevel

local DEFAULT_LEVEL = 100
local DOUBLE_STEP = 10


local generate_switch_level_event = function(device, value)
  device:emit_event(capabilities.switchLevel.level(value))
end

local generate_switch_onoff_event = function(device, value, state_change_value)
  local additional_fields = {
    state_change = state_change_value
  }
  if value == "on" then
    device:emit_event(capabilities.switch.switch.on(additional_fields))
  else
    device:emit_event(capabilities.switch.switch.off(additional_fields))
  end
end

local onoff_on_command_handler = function(driver, device, value, zb_rx)
  local level = device:get_latest_state("main", capabilities.switchLevel.ID, capabilities.switchLevel.level.NAME) or DEFAULT_LEVEL

  if level == 0 then
    generate_switch_level_event(device, DOUBLE_STEP)
  end

  generate_switch_onoff_event(device, "on", false)
end

local onoff_off_command_handler = function(driver, device, value, zb_rx)
  generate_switch_onoff_event(device, "off", false)
end

local switch_on_command_handler = function(driver, device, command)
  generate_switch_onoff_event(device, "on", true)
end

local switch_off_command_handler = function(driver, device, command)
  generate_switch_onoff_event(device, "off", true)
end

local switch_level_set_level_command_handler = function(driver, device, command)
  local level = command.args.level

  if level == 0 then
    generate_switch_onoff_event(device, "off", true)
    level = device:get_latest_state("main", capabilities.switchLevel.ID, capabilities.switchLevel.level.NAME) or 0
  else
    generate_switch_onoff_event(device, "on", true)
  end

  device.thread:call_with_delay(1, function(d)
    generate_switch_level_event(device, level)
  end)
end

local device_added = function(self, device)
  if device:get_latest_state("main", capabilities.switch.ID, capabilities.switch.switch.NAME) == nil then
    generate_switch_onoff_event(device, "on")
  end
  if device:get_latest_state("main", capabilities.switchLevel.ID, capabilities.switchLevel.level.NAME) == nil then
    generate_switch_level_event(device, DEFAULT_LEVEL)
  end
end


local zigbee_battery_accessory_dimmer = {
  NAME = "zigbee battery accessory dimmer",
  zigbee_handlers = {
    cluster = {
      [OnOff.ID] = {
        [OnOff.server.commands.On.ID] = onoff_on_command_handler,
        [OnOff.server.commands.Off.ID] = onoff_off_command_handler
      },
    }
  },
  capability_handlers = {
    [Switch.ID] = {
      [Switch.commands.on.NAME] = switch_on_command_handler,
      [Switch.commands.off.NAME] = switch_off_command_handler
    },
    [SwitchLevel.ID] = {
      [SwitchLevel.commands.setLevel.NAME] = switch_level_set_level_command_handler
    }
  },
  lifecycle_handlers = {
    added = device_added
  },
  sub_drivers = require("zigbee-battery-accessory-dimmer.sub_drivers"),
}

return zigbee_battery_accessory_dimmer
