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
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"
local window_shade_defaults = require "st.zigbee.defaults.windowShade_defaults"

local zcl_clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local TIMER = "partial_open_timer"

local function default_current_lift_percentage_handler_override(driver, device, value, zb_rx)
  local component = {id = device:get_component_id_for_endpoint(zb_rx.address_header.src_endpoint.value)}
  local last_level = device:get_latest_state(component.id, capabilities.windowShadeLevel.ID, capabilities.windowShadeLevel.shadeLevel.NAME)
  local windowShade = capabilities.windowShade.windowShade
  local event = nil
  local current_level = value.value
  if current_level ~= last_level or last_level == nil then
    last_level = last_level and last_level or 0
    device:emit_component_event(component, capabilities.windowShadeLevel.shadeLevel(current_level))
    if current_level == 0 or current_level == 100 then
      event = current_level == 0 and windowShade.closed() or windowShade.open()
    else
      event = last_level < current_level and windowShade.opening() or windowShade.closing()
    end
  end
  if event ~= nil then
    device:emit_component_event(component, event)
    local timer = device:get_field(TIMER)
    if timer ~= nil then driver:cancel_timer(timer) end
    timer = device.thread:call_with_delay(2, function(d)
      device:set_field(TIMER, nil)
      if current_level ~= 0 and current_level ~= 100 then
        device:emit_component_event(component, windowShade.partially_open())
      end
    end
    )
    device:set_field(TIMER, timer)
  end
end

window_shade_defaults.default_current_lift_percentage_handler = default_current_lift_percentage_handler_override


local function added_handler(self, device)
  device:emit_event(capabilities.windowShade.supportedWindowShadeCommands({"open", "close", "pause"}, { visibility = { displayed = false }}))
end

local zigbee_window_treatment_driver_template = {
  supported_capabilities = {
    capabilities.windowShade,
    capabilities.windowShadePreset,
    capabilities.windowShadeLevel,
    capabilities.powerSource,
    capabilities.battery
  },
  sub_drivers = {
    require("vimar"),
    require("aqara"),
    require("feibit"),
    require("somfy"),
    require("invert-lift-percentage"),
    require("rooms-beautiful"),
    require("axis"),
    require("yoolax"),
    require("hanssem"),
    require("screen-innovations")},
  lifecycle_handlers = {
    added = added_handler
  }
}

defaults.register_for_default_handlers(zigbee_window_treatment_driver_template, zigbee_window_treatment_driver_template.supported_capabilities)
local zigbee_window_treatment = ZigbeeDriver("zigbee_window_treatment", zigbee_window_treatment_driver_template)
zigbee_window_treatment:run()
