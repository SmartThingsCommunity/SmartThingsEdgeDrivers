-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-- To increase responsiveness and reduce network traffic it is recommended for a controller to subscribe to the following events: 
-- - Rotary endpoints (1,2,4,5,6,7): MultiPressOngoing and MultiPressComplete 
-- - Button endpoints (3,6,9): MultiPressOngoing, MultiPressComplete, LongPress and LongRelease. 
--    I.e., no subscriptions for InitialPress and ShortRelease. 
-- The IsUrgent flag should be set true in the subscribe request.


local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local device_lib = require "st.device"
local im = require "st.matter.interaction_model"
local log = require "log"
local utils = require "st.utils"
local switch_utils = require "utils.switch_utils"
local fields = require "utils.switch_fields"
local event_handlers = require "generic_handlers.event_handlers"

local capdefs = require "capabilities.capabilitydefs"

local knob = capabilities.build_cap_from_json_string(capdefs.knob)
capabilities["adminmirror01019.knob"] = knob

local button_subscribed_events = {
  clusters.Switch.events.MultiPressOngoing.ID,
  clusters.Switch.events.MultiPressComplete.ID,
  clusters.Switch.events.LongPress.ID,
  clusters.Switch.events.LongRelease.ID
}

local ENDPOINTS_ROTATE_RIGHT = {1, 4, 7}
local ENDPOINTS_ROTATE_LEFT = {2, 5, 8}
local ENDPOINTS_PRESS = {3, 6, 9}


local IKEA_SCROLL_FINGERPRINT = { vendor_id = 0xFFF1, product_id = 0x8000 }


-- UTIL FUNCTIONS --

local function is_ikea_scroll(opts, driver, device)
  if device.network_type == device_lib.NETWORK_TYPE_MATTER and
     device.manufacturer_info.vendor_id == IKEA_SCROLL_FINGERPRINT.vendor_id and
     device.manufacturer_info.product_id == IKEA_SCROLL_FINGERPRINT.product_id then
    log.info("Using Ikea scroll wheel sub driver")
    return true
  end
  return false
end

-- override subscribe function to prevent subscribing to additional events from the main driver
local function subscribe(device)
  local subscribe_request = im.InteractionRequest(im.InteractionRequest.RequestType.SUBSCRIBE, {})
  for _, ep_press in ipairs(ENDPOINTS_PRESS) do
    for _, switch_event in ipairs(button_subscribed_events) do
      local ib = im.InteractionInfoBlock(ep_press, clusters.Switch.ID, nil, switch_event)
      subscribe_request:with_info_block(ib)
    end
  end
  device:send(subscribe_request)
end

local function configure_buttons(device)
  local ms_eps = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH})
  for _, ep in ipairs(ms_eps) do
    if device.profile.components[switch_utils.endpoint_to_component(device, ep)] then
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
  device:set_field(fields.COMPONENT_TO_ENDPOINT_MAP, component_map, {persist = true})
end

local function match_profile(driver, device)
  device:try_update_metadata({profile = "ikea-scroll"})
  build_button_component_map(device)
  configure_buttons(device)
end


-- LIFECYCLE HANDLERS --

local IkeaScrollLifecycleHandlers = {}

function IkeaScrollLifecycleHandlers.device_added(driver, device) end -- prevent main driver device_added handling from running

function IkeaScrollLifecycleHandlers.info_changed(driver, device, event, args)
  if device.profile.id ~= args.old_st_store.profile.id then
    configure_buttons(device)
    device:subscribe()
  end
end

function IkeaScrollLifecycleHandlers.do_configure(driver, device)
  match_profile(driver, device)
end

function IkeaScrollLifecycleHandlers.driver_switched(driver, device)
  match_profile(driver, device)
end

function IkeaScrollLifecycleHandlers.device_init(driver, device)
  device:set_endpoint_to_component_fn(switch_utils.endpoint_to_component)
  device:extend_device("subscribe", subscribe)
  device:subscribe()

  device:emit_component_event(device.profile.components["group1"], knob.knob(0))
  device:emit_component_event(device.profile.components["group2"], knob.knob(0))
  device:emit_component_event(device.profile.components["group3"], knob.knob(0))
end


-- EVENT HANDLERS --

local function multi_press_ongoing_handler(driver, device, ib, response)
  if ib.data then
    local press_value = ib.data.elements.current_number_of_presses_counted.value
    local last_value = nil
    if switch_utils.get_field_for_endpoint(device, fields.MP_ONGOING, ib.endpoint_id) then
      last_value = device:get_latest_state("group1", knob.ID, knob.knob.NAME)
    end

    for _, n in ipairs(ENDPOINTS_ROTATE_RIGHT) do
      if ib.endpoint_id == n then
        local knob_value = utils.round(press_value / 18 * 100)
        if last_value ~= nil then
          knob_value = knob_value - last_value
        end
        device:emit_component_event(device.profile.components["group1"], knob.knob(knob_value))
      end
    end

    for _, n in ipairs(ENDPOINTS_ROTATE_LEFT) do
      if ib.endpoint_id == n then
        local knob_value = -utils.round(press_value / 18 * 100)
        if last_value ~= nil then
          knob_value = knob_value - last_value
        end
        device:emit_component_event(device.profile.components["group1"], knob.knob(knob_value))
      end
    end

    switch_utils.set_field_for_endpoint(device, fields.MP_ONGOING, ib.endpoint_id, true)
  end
end

local function multi_press_complete_handler(driver, device, ib, response)
  if ib.data then
    local press_value = ib.data.elements.total_number_of_presses_counted.value

    if switch_utils.get_field_for_endpoint(device, fields.MP_ONGOING, ib.endpoint_id) == nil then
      for _, n in ipairs(ENDPOINTS_ROTATE_RIGHT) do
        if ib.endpoint_id == n then
          local knob_value = utils.round(press_value / 18 * 100)
          device:emit_component_event(device.profile.components["group1"], knob.knob(knob_value))
        end
      end

      for _, n in ipairs(ENDPOINTS_ROTATE_LEFT) do
        if ib.endpoint_id == n then
          local knob_value = -utils.round(press_value / 18 * 100)
          device:emit_component_event(device.profile.components["group1"], knob.knob(knob_value))
        end
      end
    else
      switch_utils.set_field_for_endpoint(device, fields.MP_ONGOING, ib.endpoint_id, nil)
    end

    for _, n in ipairs(ENDPOINTS_PRESS) do
      if ib.endpoint_id == n then
        if not switch_utils.get_field_for_endpoint(device, fields.IGNORE_NEXT_MPC, ib.endpoint_id) then
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
    end
  end
end

local function initial_press_event_handler(driver, device, ib, response)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.button.button.pushed({state_change = true}))
end

local ikea_scroll_handler = {
  NAME = "Ikea Scroll Handler",
  lifecycle_handlers = {
    added = IkeaScrollLifecycleHandlers.device_added,
    doConfigure = IkeaScrollLifecycleHandlers.do_configure,
    driverSwitched = IkeaScrollLifecycleHandlers.driver_switched,
    infoChanged = IkeaScrollLifecycleHandlers.info_changed,
    init = IkeaScrollLifecycleHandlers.device_init,
  },
  matter_handlers = {
    event = {
      [clusters.Switch.ID] = {
        [clusters.Switch.events.MultiPressOngoing.ID] = multi_press_ongoing_handler,
        [clusters.Switch.events.MultiPressComplete.ID] = event_handlers.multi_press_complete_handler
        --[clusters.Switch.events.LongPress.ID] = long_press_handler,
       -- [clusters.Switch.events.LongRelease.ID] = long_release_handler
      }
    }
  },
  subscribed_events = {
    [capabilities.button.ID] = button_subscribed_events,
  },
  supported_capabilities = {
    capabilities.button
  },
  can_handle = is_ikea_scroll
}
