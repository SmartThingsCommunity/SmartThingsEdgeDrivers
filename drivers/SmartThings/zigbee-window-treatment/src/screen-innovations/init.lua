-- Copyright 2024 SmartThings
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

-- require st provided libraries
local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local window_preset_defaults = require "st.zigbee.defaults.windowShadePreset_defaults"
local device_management = require "st.zigbee.device_management"
local utils = require "st.utils"

local Basic = clusters.Basic
local WindowCovering = clusters.WindowCovering
local PowerConfiguration = clusters.PowerConfiguration

-- manufacturer specific cluster details
local CUS_CLU = 0xFCCC
local RUN_DIR_ATTR = 0x0012

local MOTOR_STATE = "motorState"
local MOTOR_STATE_IDLE = "idle"
local MOTOR_STATE_OPENING = "opening"
local MOTOR_STATE_CLOSING = "closing"

-----------------------------------------------------------------
-- local functions
-----------------------------------------------------------------

-- this is do_refresh
local do_refresh = function(self, device)
  device:send(WindowCovering.attributes.CurrentPositionLiftPercentage:read(device))
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:read(device))
  device:send(Basic.attributes.PowerSource:read(device))
end

-- this is window_shade_level_cmd
local function window_shade_level_cmd(driver, device, command)
  local go_to_level = command.args.shadeLevel
  -- send levels without inverting as: 0% closed (i.e., open) to 100% closed
  device:send_to_component(command.component, WindowCovering.server.commands.GoToLiftPercentage(device, go_to_level))
end

-- this is window_shade_preset_cmd
local function window_shade_preset_cmd(driver, device, command)
  local go_to_level = device.preferences.presetPosition or device:get_field(window_preset_defaults.PRESET_LEVEL_KEY) or window_preset_defaults.PRESET_LEVEL
  -- send levels without inverting as: 0% closed (i.e., open) to 100% closed
  device:send_to_component(command.component, WindowCovering.server.commands.GoToLiftPercentage(device, go_to_level))
end

-- this is device_added
local function device_added(self, device)
  device:emit_event(capabilities.windowShade.supportedWindowShadeCommands({ "open", "close", "pause" }, {visibility = {displayed = false}}))
  -- initialize motor state
  device:set_field(MOTOR_STATE, MOTOR_STATE_IDLE)
  device.thread:call_with_delay(3, function(d)
    do_refresh(self, device)
  end)
end

-- this is current_position_attr_handler
local function current_position_attr_handler(driver, device, value, zb_rx)
  local level = value.value
  local event = nil
  local motor_state_value = device:get_field(MOTOR_STATE) or MOTOR_STATE_IDLE

  -- when the device is in action
  if motor_state_value == MOTOR_STATE_OPENING then
    event = capabilities.windowShade.windowShade.opening()
  end

  if motor_state_value == MOTOR_STATE_CLOSING then
    event = capabilities.windowShade.windowShade.closing()
  end

  -- when the device is in idle
  if motor_state_value == MOTOR_STATE_IDLE then
    if level == 0 then
      event = capabilities.windowShade.windowShade.open()
    elseif level == 100 then
      event = capabilities.windowShade.windowShade.closed()
    else
      event = capabilities.windowShade.windowShade.partially_open()
    end
  end

  -- update status
  if event ~= nil then
    device:emit_event(event)
  end

  -- update level
  device:emit_event(capabilities.windowShadeLevel.shadeLevel(level))
end

-- this is motor running_direction_attr_handler
local function running_direction_attr_handler(driver, device, value, zb_rx)
  local status = value.value
  if status == 1 then
    device:set_field(MOTOR_STATE, MOTOR_STATE_OPENING)
  elseif status == 2 then
    device:set_field(MOTOR_STATE, MOTOR_STATE_CLOSING)
  else
    device:set_field(MOTOR_STATE, MOTOR_STATE_IDLE)
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
  local motor_state_value = device:get_field(MOTOR_STATE) or ""
  -- update battery percentage only motor is in idle state
  if motor_state_value == MOTOR_STATE_IDLE then
    device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value,
      capabilities.battery.battery(utils.clamp_value(converted_value, 0, 100)))
  end
end

-- create the handler object
local screeninnovations_roller_shade_handler = {
  NAME = "screeninnovations_roller_shade_handler",
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
      },
      [CUS_CLU] = {
        [RUN_DIR_ATTR] = running_direction_attr_handler,
      }
    }
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_model() == "WM25/L-Z"
  end
}

-- return the handler
return screeninnovations_roller_shade_handler
