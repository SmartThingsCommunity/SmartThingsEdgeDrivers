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
local zcl_global_commands = require "st.zigbee.zcl.global_commands"
local Status = require "st.zigbee.generated.types.ZclStatus"
local WindowCovering = zcl_clusters.WindowCovering

local device_management = require "st.zigbee.device_management"

local LEVEL_UPDATE_TIMEOUT = "__level_update_timeout"
local MOST_RECENT_SETLEVEL = "__most_recent_setlevel"

local YOOLAX_WINDOW_SHADE_FINGERPRINTS = {
    { mfr = "Yookee", model = "D10110" },                                 -- Yookee Window Treatment
    { mfr = "yooksmart", model = "D10110" }                               -- yooksmart Window Treatment
}

local function is_yoolax_window_shade(opts, driver, device)
  for _, fingerprint in ipairs(YOOLAX_WINDOW_SHADE_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function default_response_handler(driver, device, zb_message)
  local is_success = zb_message.body.zcl_body.status.value
  local command = zb_message.body.zcl_body.cmd.value

  if is_success == Status.SUCCESS and command == WindowCovering.server.commands.GoToLiftPercentage.ID then
    local current_level = device:get_latest_state("main", capabilities.windowShadeLevel.ID, capabilities.windowShadeLevel.shadeLevel.NAME)
    if current_level then current_level = 100 - current_level end -- convert to the zigbee value
    local most_recent_setlevel = device:get_field(MOST_RECENT_SETLEVEL)
    if current_level and most_recent_setlevel and current_level ~= most_recent_setlevel then
      if current_level > most_recent_setlevel then
        device:emit_event(capabilities.windowShade.windowShade.opening())
      else
        device:emit_event(capabilities.windowShade.windowShade.closing())
      end
    end
  end
end

local function set_shade_level(driver, device, value, command)
  local level = 100 - value
  device:send_to_component(command.component, WindowCovering.server.commands.GoToLiftPercentage(device, level))
  device:set_field(MOST_RECENT_SETLEVEL, level) -- set the value to the zigbee protocol value

  local timer = device:get_field(LEVEL_UPDATE_TIMEOUT)
  if timer then
    device.thread.cancel_timer(timer)
  end
  timer = device.thread:call_with_delay(30, function ()
    -- for some reason the device isn't updating us about its state so we'll send another bind request
    device:send(device_management.build_bind_request(device, WindowCovering.ID, driver.environment_info.hub_zigbee_eui))
    device:send(WindowCovering.attributes.CurrentPositionLiftPercentage:configure_reporting(device, 0, 600, 1))
    device:send_to_component(command.component, WindowCovering.attributes.CurrentPositionLiftPercentage:read(device))
    device:set_field(LEVEL_UPDATE_TIMEOUT, nil)
  end)
  device:set_field(LEVEL_UPDATE_TIMEOUT, timer)
end

local function window_shade_level_cmd(driver, device, command)
  set_shade_level(driver, device, command.value, command)
end

local function window_shade_preset_cmd(driver, device, command)
  set_shade_level(driver, device, device.preferences.presetPosition, command)
end

local function set_window_shade_level(level)
  return function(driver, device, cmd)
    set_shade_level(driver, device, level, cmd)
  end
end

local function current_position_attr_handler(driver, device, value, zb_rx)
  local current_level = device:get_latest_state("main", capabilities.windowShadeLevel.ID, capabilities.windowShadeLevel.shadeLevel.NAME)
  if current_level then current_level = 100 - current_level end -- convert to the zigbee value

  if value.value == 0 then
    device:emit_event(capabilities.windowShade.windowShade.open())
  elseif value.value == 100 then
    device:emit_event(capabilities.windowShade.windowShade.closed())
  elseif current_level == nil then
    -- our first level change to a non-open/closed value
    device:emit_event(capabilities.windowShade.windowShade.partially_open())
  end

  local most_recent_setlevel = device:get_field(MOST_RECENT_SETLEVEL)
  if most_recent_setlevel and value.value == most_recent_setlevel then
    -- this is a report matching our most recent set level command, assume we've stopped
    device:set_field(MOST_RECENT_SETLEVEL, nil)
    if value.value ~= 0 and value.value ~= 100 then
      device:emit_event(capabilities.windowShade.windowShade.partially_open())
    end
    local timer = device:get_field(LEVEL_UPDATE_TIMEOUT)
    if timer then
      device.thread:cancel_timer(timer)
      device:set_field(LEVEL_UPDATE_TIMEOUT, nil)
    end
  elseif most_recent_setlevel == nil then
    -- this is a spontaneous level change
    if current_level and current_level ~= value.value then
      if current_level > value.value then
        device:emit_event(capabilities.windowShade.windowShade.opening())
      else
        device:emit_event(capabilities.windowShade.windowShade.closing())
      end
      device.thread:call_with_delay(2, function()
        -- if we don't have a changed level value within the next 2s, assume we've stopped moving
        local current_level_now = device:get_latest_state("main", capabilities.windowShadeLevel.ID, capabilities.windowShadeLevel.shadeLevel.NAME)
        if current_level_now then current_level_now = 100 - current_level_now end -- convert to the zigbee value
        if current_level_now == value.value and current_level_now ~= 0 and current_level_now ~= 100 then
          device:emit_event(capabilities.windowShade.windowShade.partially_open())
        end
      end)
    end
  end
  device:emit_event(capabilities.windowShadeLevel.shadeLevel(100 - value.value))
end

local yoolax_window_shade = {
  NAME = "yoolax window shade",
  capability_handlers = {
    [capabilities.windowShade.ID] = {
      [capabilities.windowShadeLevel.commands.setShadeLevel.NAME] = window_shade_level_cmd,
      [capabilities.windowShade.commands.open.NAME] = set_window_shade_level(100), -- a report of 0 = open
      [capabilities.windowShade.commands.close.NAME] = set_window_shade_level(0), -- a report of 100 = closed
    },
    [capabilities.windowShadePreset.ID] = {
      [capabilities.windowShadePreset.commands.presetPosition.NAME] = window_shade_preset_cmd
    }
  },
  zigbee_handlers = {
    attr = {
      [WindowCovering.ID] = {
        [WindowCovering.attributes.CurrentPositionLiftPercentage.ID] = current_position_attr_handler
      }
    },
    global = {
      [WindowCovering.ID] = {
        [zcl_global_commands.DEFAULT_RESPONSE_ID] = default_response_handler
      }
    },
  },
  can_handle = is_yoolax_window_shade
}

return yoolax_window_shade
