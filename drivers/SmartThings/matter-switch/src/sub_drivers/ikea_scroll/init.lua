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
local device_lib = require "st.device"
local im = require "st.matter.interaction_model"
local log = require "log"

local COMPONENT_TO_ENDPOINT_MAP = "__component_to_endpoint_map"

local ENDPOINTS_ROTATE_RIGHT = {1, 4, 7}
local ENDPOINTS_ROTATE_LEFT = {2, 5, 8}
local ENDPOINTS_PRESS = {3, 6, 9}


local IKEA_SCROLL_FINGERPRINT = { vendor_id = 0xFFF1, product_id = 0x8000 }

local function is_ikea_scroll(opts, driver, device)
  if device.network_type == device_lib.NETWORK_TYPE_MATTER and
     device.manufacturer_info.vendor_id == IKEA_SCROLL_FINGERPRINT.vendor_id and
     device.manufacturer_info.product_id == IKEA_SCROLL_FINGERPRINT.product_id then
    log.info("Using Ikea scroll wheel sub driver")
    return true
  end
  return false
end

local function endpoint_to_component(device, ep)
  local map = device:get_field(COMPONENT_TO_ENDPOINT_MAP) or {}
  for component, endpoint in pairs(map) do
    if endpoint == ep then
      return component
    end
  end
  return "main"
end

local function subscribe_to_switch_event(endpoint, event)
  local ib = im.InteractionInfoBlock(endpoint, clusters.Switch.ID, nil, event)
  local subscribe_request = im.InteractionRequest(im.InteractionRequest.RequestType.SUBSCRIBE, {})
  subscribe_request:with_info_block(ib)
  device:send(subscribe_request)
end

-- override subscribe function to prevent subscribing to additional events from the main driver
local function subscribe(device)
  for _, n in ipairs(ENDPOINTS_ROTATE_RIGHT + ENDPOINTS_ROTATE_LEFT) do
    subscribe_to_switch_event(n, clusters.Switch.events.MultiPressOngoing.ID)
    subscribe_to_switch_event(n, clusters.Switch.events.MultiPressComplete.ID)
  end

  for _, n in ipairs(ENDPOINTS_PRESS) do
    subscribe_to_switch_event(n, clusters.Switch.events.MultiPressOngoing.ID)
    subscribe_to_switch_event(n, clusters.Switch.events.MultiPressComplete.ID)
    subscribe_to_switch_event(n, clusters.Switch.events.LongPress.ID)
    subscribe_to_switch_event(n, clusters.Switch.events.LongRelease.ID)
  end
  
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
  component_map["group1"] = button_eps[3]
  component_map["group2"] = button_eps[6]
  component_map["group3"] = button_eps[9]
  device:set_field(COMPONENT_TO_ENDPOINT_MAP, component_map, {persist = true})
end

local function device_init(driver, device)
  device:set_endpoint_to_component_fn(endpoint_to_component)
  device:extend_device("subscribe", subscribe)
  device:subscribe()

  device:emit_component_event('group1', capabilities.switchLevel.level(50))
  device:emit_component_event('group2', capabilities.switchLevel.level(50))
  device:emit_component_event('group3', capabilities.switchLevel.level(50))
end

-- override device_added to prevent it running in the main driver
local function device_added(driver, device) 

end

local function info_changed(driver, device, event, args)
  if device.profile.id ~= args.old_st_store.profile.id then
    configure_buttons(device)
    device:subscribe()
  end
end

local function match_profile(driver, device)
  device:try_update_metadata({profile = "ikea-scroll"})
  build_button_component_map(device)
  configure_buttons(device)
end

local function do_configure(driver, device)
  match_profile(driver, device)
end

local function driver_switched(driver, device)
  match_profile(driver, device)
end

function multi_press_complete_handler(driver, device, ib, response)
  if ib.data then
    local press_value = ib.data.elements.total_number_of_presses_counted.value
    --if ib.endpoint_id in ENDPOINTS_ROTATE_RIGHT then 
    --end
  end



  if ib.data and not switch_utils.get_field_for_endpoint(device, fields.IGNORE_NEXT_MPC, ib.endpoint_id) then
    local press_value = ib.data.elements.total_number_of_presses_counted.value
    --capability only supports up to 6 presses
    if press_value < 7 then
      local button_event = capabilities.button.button.pushed({state_change = true})
      if press_value == 2 then
        button_event = capabilities.button.button.double({state_change = true})
      elseif press_value > 2 then
        button_event = capabilities.button.button(string.format("pushed_%dx", press_value), {state_change = true})
      end

      device:emit_event_for_endpoint(ib.endpoint_id, button_event)
    else
      device.log.info(string.format("Number of presses (%d) not supported by capability", press_value))
    end
  end
  switch_utils.set_field_for_endpoint(device, fields.IGNORE_NEXT_MPC, ib.endpoint_id, nil)
end

local function initial_press_event_handler(driver, device, ib, response)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.button.button.pushed({state_change = true}))
end

local ikea_scroll_handler = {
  NAME = "Ikea Scroll Handler",
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
        --[clusters.Switch.events.MultiPressOngoing.ID] = multi_press_ongoing,
        [clusters.Switch.events.MultiPressComplete.ID] = multi_press_complete_handler
        --[clusters.Switch.events.LongPress.ID] = long_press_handler,
       -- [clusters.Switch.events.LongRelease.ID] = long_release_handler
      }
    }
  },
  supported_capabilities = {
    capabilities.button
  },
  can_handle = is_ikea_scroll
}

return ikea_scroll_handler
