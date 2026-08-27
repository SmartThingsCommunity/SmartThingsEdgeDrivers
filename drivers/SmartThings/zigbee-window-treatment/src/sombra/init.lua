-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


-- require st provided libraries
local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local window_shade_utils = require "window_shade_utils"
local device_management = require "st.zigbee.device_management"
local utils = require "st.utils"

local Basic = clusters.Basic
local WindowCovering = clusters.WindowCovering
local PowerConfiguration = clusters.PowerConfiguration

-- Sombra motors report position in the shade-industry convention
-- (0% = open, 100% = closed), which is passed straight through to
-- windowShadeLevel.shadeLevel with no inversion.
--
-- Opening/Closing status is inferred from the direction the position is
-- changing, so it works on every Sombra motor variant -- battery and DC --
-- regardless of any manufacturer-specific motion cluster. When position
-- reports stop arriving, a short settle timer emits the resting state.
local SETTLE_DELAY = 3
local SETTLE_TIMER = "shade_settle_timer"

-----------------------------------------------------------------
-- local functions
-----------------------------------------------------------------

-- emit the resting windowShade state for a level (0 = open, 100 = closed)
local function emit_resting_state(device, level)
  if level <= 0 then
    device:emit_event(capabilities.windowShade.windowShade.open())
  elseif level >= 100 then
    device:emit_event(capabilities.windowShade.windowShade.closed())
  else
    device:emit_event(capabilities.windowShade.windowShade.partially_open())
  end
end

-- cancel any pending settle timer
local function cancel_settle_timer(device)
  local timer = device:get_field(SETTLE_TIMER)
  if timer then
    device.thread:cancel_timer(timer)
    device:set_field(SETTLE_TIMER, nil)
  end
end

-- (re)start the settle timer; when it fires without a newer position report
-- the shade has stopped moving, so emit the resting state
local function schedule_settle(device)
  cancel_settle_timer(device)
  local timer = device.thread:call_with_delay(SETTLE_DELAY, function()
    device:set_field(SETTLE_TIMER, nil)
    local level = device:get_latest_state("main", capabilities.windowShadeLevel.ID,
      capabilities.windowShadeLevel.shadeLevel.NAME) or 0
    emit_resting_state(device, level)
  end)
  device:set_field(SETTLE_TIMER, timer)
end

-- this is do_refresh
local do_refresh = function(self, device)
  device:send(WindowCovering.attributes.CurrentPositionLiftPercentage:read(device))
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:read(device))
  device:send(Basic.attributes.PowerSource:read(device))
end

-- this is window_shade_level_cmd
local function window_shade_level_cmd(driver, device, command)
  local go_to_level = command.args.shadeLevel
  -- send levels without inverting as: 0% lift (open) to 100% lift (closed)
  device:send_to_component(command.component, WindowCovering.server.commands.GoToLiftPercentage(device, go_to_level))
end

-- this is window_shade_preset_cmd
local function window_shade_preset_cmd(driver, device, command)
  local level = window_shade_utils.get_preset_level(device, command.component)
  -- send levels without inverting as: 0% lift (open) to 100% lift (closed)
  device:send_to_component(command.component, WindowCovering.server.commands.GoToLiftPercentage(device, level))
end

-- this is device_added
local function device_added(self, device)
  device:emit_event(capabilities.windowShade.supportedWindowShadeCommands({ "open", "close", "pause" }, {visibility = {displayed = false}}))
  device.thread:call_with_delay(3, function(d)
    do_refresh(self, device)
  end)
end

-- this is current_position_attr_handler
-- position is 0 = open, 100 = closed; direction is inferred from the change
local function current_position_attr_handler(driver, device, value, zb_rx)
  local level = value.value
  local previous = device:get_latest_state("main", capabilities.windowShadeLevel.ID,
    capabilities.windowShadeLevel.shadeLevel.NAME) or 0
  local windowShade = capabilities.windowShade.windowShade

  device:emit_event(capabilities.windowShadeLevel.shadeLevel(level))

  if level <= 0 then
    cancel_settle_timer(device)
    device:emit_event(windowShade.open())
  elseif level >= 100 then
    cancel_settle_timer(device)
    device:emit_event(windowShade.closed())
  else
    if level < previous then
      device:emit_event(windowShade.opening())
    elseif level > previous then
      device:emit_event(windowShade.closing())
    end
    schedule_settle(device)
  end
end

-- this is do_configure
local function do_configure(self, device)
  -- configure elements
  device:send(device_management.build_bind_request(device, WindowCovering.ID, self.environment_info.hub_zigbee_eui))
  device:send(WindowCovering.attributes.CurrentPositionLiftPercentage:configure_reporting(device, 1, 3600, 1))
  device:send(device_management.build_bind_request(device, PowerConfiguration.ID, self.environment_info.hub_zigbee_eui))
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(device, 1, 3600, 1))
  device:send(device_management.build_bind_request(device, Basic.ID, self.environment_info.hub_zigbee_eui))
  device:send(Basic.attributes.PowerSource:configure_reporting(device, 1, 3600))

  -- read elements
  device.thread:call_with_delay(3, function(d)
    do_refresh(self, device)
  end)
end

-- this is battery_perc_attr_handler
local function battery_perc_attr_handler(driver, device, value, zb_rx)
  local converted_value = value.value / 2
  converted_value = utils.round(converted_value)
  device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value,
    capabilities.battery.battery(utils.clamp_value(converted_value, 0, 100)))
end

-- create the handler object
local sombra_roller_shade_handler = {
  NAME = "sombra_roller_shade_handler",
  lifecycle_handlers = {
    added = device_added,
    doConfigure = do_configure
  },
  capability_handlers = {
    [capabilities.windowShadeLevel.ID] = {
      [capabilities.windowShadeLevel.commands.setShadeLevel.NAME] = window_shade_level_cmd
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
      [WindowCovering.ID] = {
        [WindowCovering.attributes.CurrentPositionLiftPercentage.ID] = current_position_attr_handler,
      },
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryPercentageRemaining.ID] = battery_perc_attr_handler,
      }
    }
  },
  can_handle = require("sombra.can_handle"),
}

-- return the handler
return sombra_roller_shade_handler
