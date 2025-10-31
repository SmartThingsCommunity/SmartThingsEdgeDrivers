-- Copyright 2025 SmartThings
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

local zcl_clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local custom_clusters = require "VIVIDSTORM/custom_clusters"
local cluster_base = require "st.zigbee.cluster_base"
local WindowCovering = zcl_clusters.WindowCovering

local MOST_RECENT_SETLEVEL = "windowShade_recent_setlevel"
local TIMER = "liftPercentage_timer"


local ZIGBEE_WINDOW_SHADE_FINGERPRINTS = {
  { mfr = "VIVIDSTORM", model = "VWSDSTUST120H" }
}

local is_zigbee_window_shade = function(opts, driver, device)
  for _, fingerprint in ipairs(ZIGBEE_WINDOW_SHADE_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function send_read_attr_request(device, cluster, attr)
  device:send(
    cluster_base.read_manufacturer_specific_attribute(
      device,
      cluster.id,
      attr.id,
      cluster.mfg_specific_code
    )
  )
end

local mode_str = { "Delete upper limit","Set the upper limit","Delete lower limit","Set the lower limit" }

local function mode_attr_handler(driver, device, value, zb_rx)
  if value.value <= 3 then
    local value = mode_str[value.value+1]
    if value ~= nil then
      device:emit_component_event(device.profile.components.main,capabilities.mode.mode(value))
    end
  end
end


local function liftPercentage_attr_handler(driver, device, value, zb_rx)
  local windowShade = capabilities.windowShade.windowShade
  local components = device.profile.components.main
  local most_recent_setlevel = device:get_field(MOST_RECENT_SETLEVEL)
    if value.value and most_recent_setlevel and value.value ~= most_recent_setlevel then
      if value.value > most_recent_setlevel then
        device:emit_component_event(components,windowShade.opening())
      elseif value.value < most_recent_setlevel then
        device:emit_component_event(components,windowShade.closing())
      end
    end
  device:set_field(MOST_RECENT_SETLEVEL, value.value)

  local timer = device:get_field(TIMER)
  if timer ~= nil then driver:cancel_timer(timer) end
  timer = device.thread:call_with_delay(5, function(d)
    if most_recent_setlevel == 0 then
      device:emit_component_event(components,windowShade.closed())
    elseif most_recent_setlevel == 100 then
      device:emit_component_event(components,windowShade.open())
    else
      device:emit_component_event(components,windowShade.partially_open())
    end
  end
  )
  device:set_field(TIMER, timer)
end

local function hardwareFault_attr_handler(driver, device, value, zb_rx)
  if value.value == 1 then
    device:emit_component_event(device.profile.components.hardwareFault,capabilities.hardwareFault.hardwareFault.detected())
  elseif value.value == 0 then
    device:emit_component_event(device.profile.components.hardwareFault,capabilities.hardwareFault.hardwareFault.clear())
  end
end

local function capabilities_mode_handler(driver, device, command)
  local value = 0
  if command.args.mode == "Delete upper limit" then
    value = 0
  elseif command.args.mode == "Set the upper limit" then
    value = 1
  elseif command.args.mode == "Delete lower limit" then
    value = 2
  elseif command.args.mode == "Set the lower limit" then
    value = 3
  end

  device:send(
    cluster_base.write_manufacturer_specific_attribute(
      device,
      custom_clusters.motor.id,
      custom_clusters.motor.attributes.mode_value.id,
      custom_clusters.motor.mfg_specific_code,
      custom_clusters.motor.attributes.mode_value.value_type,
      value
    )
  )
end

local function do_refresh(driver, device)
  device:send(WindowCovering.attributes.CurrentPositionLiftPercentage:read(device):to_endpoint(0x01))
  send_read_attr_request(device, custom_clusters.motor, custom_clusters.motor.attributes.mode_value)
  send_read_attr_request(device, custom_clusters.motor, custom_clusters.motor.attributes.hardwareFault)
end

local function added_handler(self, device)
  device:emit_component_event(device.profile.components.hardwareFault,capabilities.hardwareFault.hardwareFault.clear())
  do_refresh(self, device)
end

local screen_handler = {
  NAME = "VWSDSTUST120H Device Handler",
  supported_capabilities = {
    capabilities.refresh
  },
  lifecycle_handlers = {
    added = added_handler
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    },
    [capabilities.mode.ID] = {
      [capabilities.mode.commands.setMode.NAME] = capabilities_mode_handler
    },
  },
  zigbee_handlers = {
    attr = {
      [WindowCovering.ID] = {
        [WindowCovering.attributes.CurrentPositionLiftPercentage.ID] = liftPercentage_attr_handler
      },
      [custom_clusters.motor.id] = {
        [custom_clusters.motor.attributes.mode_value.id] = mode_attr_handler,
        [custom_clusters.motor.attributes.hardwareFault.id] = hardwareFault_attr_handler
      }
    }
  },
  can_handle = is_zigbee_window_shade,
}

return screen_handler
