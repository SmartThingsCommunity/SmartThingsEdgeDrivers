-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local device_management = require "st.zigbee.device_management"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"

local zcl_clusters = require "st.zigbee.zcl.clusters"
local Level = zcl_clusters.Level
local OnOff = zcl_clusters.OnOff

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
  handleStepEvent(device, zcl_clusters.Level.types.MoveStepMode.DOWN)
end

local level_move_with_onoff_command_handler = function(driver, device, zb_rx)
  handleStepEvent(device, zcl_clusters.Level.types.MoveStepMode.UP)
end

local do_configure = function(self, device)
  device:refresh()
  device:configure()

  device:send(device_management.build_bind_request(device, OnOff.ID, self.environment_info.hub_zigbee_eui))
  device:send(device_management.build_bind_request(device, Level.ID, self.environment_info.hub_zigbee_eui))
end


local voltage_configuration = {
  cluster = zcl_clusters.PowerConfiguration.ID,
  attribute = zcl_clusters.PowerConfiguration.attributes.BatteryVoltage.ID,
  minimum_interval = 30,
  maximum_interval = 14300,
  data_type = zcl_clusters.PowerConfiguration.attributes.BatteryVoltage.base_type,
  reportable_change = 1
}

local function device_init(driver, device)
  device:add_configured_attribute(voltage_configuration)
  device:remove_monitored_attribute(zcl_clusters.PowerConfiguration.ID, zcl_clusters.PowerConfiguration.attributes.BatteryPercentageRemaining.ID)
  device:remove_configured_attribute(zcl_clusters.PowerConfiguration.ID, zcl_clusters.PowerConfiguration.attributes.BatteryPercentageRemaining.ID)
  device:set_field(battery_defaults.DEVICE_MIN_VOLTAGE_KEY, 2.3)
  device:set_field(battery_defaults.DEVICE_MAX_VOLTAGE_KEY, 3.0)
end

local centralite_systems = {
  NAME = "centralite systems",
  zigbee_handlers = {
    cluster = {
      [Level.ID] = {
        [Level.server.commands.Move.ID] = level_move_command_handler,
        [Level.server.commands.MoveWithOnOff.ID] = level_move_with_onoff_command_handler,
      }
    }
  },
  lifecycle_handlers = {
    init = device_init,
    doConfigure = do_configure
  },
  can_handle = require("zigbee-battery-accessory-dimmer.CentraliteSystems.can_handle"),
}

return centralite_systems
