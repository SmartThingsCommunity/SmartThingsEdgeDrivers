-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local utils = require 'st.utils'
local zcl_clusters = require "st.zigbee.zcl.clusters"

local Level = zcl_clusters.Level
local PowerConfiguration = zcl_clusters.PowerConfiguration

local capabilities = require "st.capabilities"

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

local handleStepEvent = function(device, direction)
  local level = device:get_latest_state("main", capabilities.switchLevel.ID, capabilities.switchLevel.level.NAME) or DEFAULT_LEVEL
  local value = 0

  if direction == zcl_clusters.Level.types.MoveStepMode.UP  then
    value = math.min(level + DOUBLE_STEP, 100)
  elseif direction == zcl_clusters.Level.types.MoveStepMode.DOWN then
    value = math.max(level - DOUBLE_STEP, 0)
  end

  if value == 0 then
    generate_switch_onoff_event(device, "off", false)
  else
    generate_switch_onoff_event(device, "on", false)
    generate_switch_level_event(device, value)
  end
end

local level_move_command_handler = function(driver, device, zb_rx)
  local move_mode = zb_rx.body.zcl_body.move_mode.value
  handleStepEvent(device, move_mode)
end

local level_move_with_onoff_command_handler = function(driver, device, zb_rx)
  local move_mode = zb_rx.body.zcl_body.move_mode.value
  handleStepEvent(device, move_mode)
end

local level_move_to_level_with_onoff_command_handler = function(driver, device, zb_rx)
  local level = zb_rx.body.zcl_body.level.value

  if level == 0x00 then
    generate_switch_onoff_event(device, "on", true)
  elseif level == 0xFF then
    local current_level = device:get_latest_state("main", capabilities.switchLevel.ID, capabilities.switchLevel.level.NAME) or DEFAULT_LEVEL
    if current_level == 0 then
      generate_switch_level_event(device, DOUBLE_STEP)
    end

    generate_switch_onoff_event(device, "on", true)
  else
    generate_switch_onoff_event(device, "on", true)

    device:send(zcl_clusters.Level.server.commands.MoveToLevelWithOnOff(device, level))
  end
  handleStepEvent(device, level)
end

local level_step_command_handler = function(driver, device, zb_rx)
  local move_mode = zb_rx.body.zcl_body.step_mode.value
  handleStepEvent(device, move_mode)
end

local battery_perc_attr_handler = function(driver, device, value, zb_rx)
  device:emit_event(capabilities.battery.battery(utils.clamp_value(value.value, 0, 100)))
end


local ikea_of_sweden = {
  NAME = "IKEA of Sweden",
  zigbee_handlers = {
    cluster = {
      [Level.ID] = {
        [Level.server.commands.Move.ID] = level_move_command_handler,
        [Level.server.commands.MoveWithOnOff.ID] = level_move_with_onoff_command_handler,
        [Level.server.commands.MoveToLevelWithOnOff.ID] = level_move_to_level_with_onoff_command_handler,
        [Level.server.commands.Step.ID] = level_step_command_handler
      }
    },
    attr = {
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryPercentageRemaining.ID] = battery_perc_attr_handler
      }
    }
  },
  can_handle = require("zigbee-battery-accessory-dimmer.IKEAofSweden.can_handle"),
}

return ikea_of_sweden
