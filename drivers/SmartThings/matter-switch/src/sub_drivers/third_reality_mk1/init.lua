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

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local im = require "st.matter.interaction_model"

local COMPONENT_TO_ENDPOINT_MAP = "__component_to_endpoint_map"

-------------------------------------------------------------------------------------
-- Third Reality MK1 specifics
-------------------------------------------------------------------------------------

local function endpoint_to_component(device, ep)
  local map = device:get_field(COMPONENT_TO_ENDPOINT_MAP) or {}
  for component, endpoint in pairs(map) do
    if endpoint == ep then
      return component
    end
  end
  return "main"
end

-- override subscribe function to prevent subscribing to additional events from the main driver
local function subscribe(device)
  local ib = im.InteractionInfoBlock(nil, clusters.Switch.ID, nil, clusters.Switch.events.InitialPress.ID)
  local subscribe_request = im.InteractionRequest(im.InteractionRequest.RequestType.SUBSCRIBE, {})
  subscribe_request:with_info_block(ib)
  device:send(subscribe_request)
end

local function configure_buttons(device)
  local ms_eps = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH})
  for _, ep in ipairs(ms_eps) do
    if device.profile.components[endpoint_to_component(device, ep)] then
      device.log.info(string.format("Configuring Supported Values for generic switch endpoint %d", ep))
      local supportedButtonValues_event = capabilities.button.supportedButtonValues({"pushed"}, {visibility = {displayed = false}})
      device:emit_event_for_endpoint(ep, supportedButtonValues_event)
      device:emit_event_for_endpoint(ep, capabilities.button.button.pushed({state_change = false}))
    else
      device.log.info(string.format("Component not found for generic switch endpoint %d. Skipping Supported Value configuration", ep))
    end
  end
end

local function build_button_component_map(device)
  local button_eps = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH})
  table.sort(button_eps)
  local component_map = {}
  component_map["main"] = button_eps[1]
  for component_num = 2, 12 do
    component_map["F" .. component_num] = button_eps[component_num]
  end
  device:set_field(COMPONENT_TO_ENDPOINT_MAP, component_map, {persist = true})
end

local function device_init(driver, device)
  device:set_endpoint_to_component_fn(endpoint_to_component)
  device:extend_device("subscribe", subscribe)
  device:subscribe()
end

-- override device_added to prevent it running in the main driver
local function device_added(driver, device) end

local function info_changed(driver, device, event, args)
  if device.profile.id ~= args.old_st_store.profile.id then
    configure_buttons(device)
    device:subscribe()
  end
end

local function match_profile(driver, device)
  device:try_update_metadata({profile = "12-button-keyboard"})
  build_button_component_map(device)
  configure_buttons(device)
end

local function do_configure(driver, device)
  match_profile(driver, device)
end

local function driver_switched(driver, device)
  match_profile(driver, device)
end

local function initial_press_event_handler(driver, device, ib, response)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.button.button.pushed({state_change = true}))
end

local third_reality_mk1_handler = {
  NAME = "ThirdReality MK1 Handler",
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    infoChanged = info_changed,
    doConfigure = do_configure,
    driverSwitched = driver_switched
  },
  matter_handlers = {
    event = {
      [clusters.Switch.ID] = {
        [clusters.Switch.events.InitialPress.ID] = initial_press_event_handler
      }
    }
  },
  supported_capabilities = {
    capabilities.button
  },
  can_handle = require("sub_drivers.third_reality_mk1.can_handle")
}

return third_reality_mk1_handler
