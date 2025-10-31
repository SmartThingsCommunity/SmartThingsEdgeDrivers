-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local device_lib = require "st.device"
local im = require "st.matter.interaction_model"
local switch_utils = require "utils.switch_utils"
local fields = require "utils.switch_fields"

local IKEA_SCROLL_FINGERPRINT = { vendor_id = 0xFFF1, product_id = 0x8000 }

local ENDPOINTS_PRESS = {3, 6, 9}

local button_subscribed_events = {
  clusters.Switch.events.MultiPressComplete.ID,
  clusters.Switch.events.LongPress.ID,
}


-- UTIL FUNCTIONS --

local ikea_scroll_utils = {}

function ikea_scroll_utils.is_ikea_scroll(opts, driver, device)
  if device.network_type == device_lib.NETWORK_TYPE_MATTER and
     device.manufacturer_info.vendor_id == IKEA_SCROLL_FINGERPRINT.vendor_id and
     device.manufacturer_info.product_id == IKEA_SCROLL_FINGERPRINT.product_id then
    device.log.info("Using Ikea scroll wheel sub driver")
    return true
  end
  return false
end

-- override subscribe function to prevent subscribing to additional events from the main driver
function ikea_scroll_utils.subscribe(device)
  local subscribe_request = im.InteractionRequest(im.InteractionRequest.RequestType.SUBSCRIBE, {})
  for _, ep_press in ipairs(ENDPOINTS_PRESS) do
    for _, switch_event in ipairs(button_subscribed_events) do
      local ib = im.InteractionInfoBlock(ep_press, clusters.Switch.ID, nil, switch_event)
      subscribe_request:with_info_block(ib)
    end
  end
  device:send(subscribe_request)
end

function ikea_scroll_utils.build_button_component_map(device)
  local component_map = {
    group1 = ENDPOINTS_PRESS[1],
    group2 = ENDPOINTS_PRESS[2],
    group3 = ENDPOINTS_PRESS[3],
  }
  device:set_field(fields.COMPONENT_TO_ENDPOINT_MAP, component_map, {persist = true})
end

function ikea_scroll_utils.configure_buttons(device)
  for _, ep_press in ipairs(ENDPOINTS_PRESS) do
    if device.profile.components[switch_utils.endpoint_to_component(device, ep_press)] then
      device.log.info(string.format("Configuring Supported Values for generic switch endpoint %d", ep_press))
      device:send(clusters.Switch.attributes.MultiPressMax:read(device, ep_press))
      device:emit_event_for_endpoint(ep_press, capabilities.button.button.pushed({state_change = false}))
    else
      device.log.info(string.format("Component not found for generic switch endpoint %d. Skipping Supported Value configuration", ep_press))
    end
  end
end

function ikea_scroll_utils.match_profile(driver, device)
  device:try_update_metadata({profile = "ikea-scroll"})
  ikea_scroll_utils.build_button_component_map(device)
  ikea_scroll_utils.configure_buttons(device)
end


-- LIFECYCLE HANDLERS --

local IkeaScrollLifecycleHandlers = {}

-- prevent main driver device_added handling from running
function IkeaScrollLifecycleHandlers.device_added(driver, device)
end

function IkeaScrollLifecycleHandlers.device_init(driver, device)
  device:set_endpoint_to_component_fn(switch_utils.endpoint_to_component)
  device:extend_device("subscribe", ikea_scroll_utils.subscribe)
  device:subscribe()
end

function IkeaScrollLifecycleHandlers.do_configure(driver, device)
  ikea_scroll_utils.match_profile(driver, device)
end

function IkeaScrollLifecycleHandlers.driver_switched(driver, device)
  ikea_scroll_utils.match_profile(driver, device)
end

function IkeaScrollLifecycleHandlers.info_changed(driver, device, event, args)
  if device.profile.id ~= args.old_st_store.profile.id then
    ikea_scroll_utils.configure_buttons(device)
    device:subscribe()
  end
end


-- DEVICE TEMPLATE --

local ikea_scroll_handler = {
  NAME = "Ikea Scroll Handler",
  lifecycle_handlers = {
    added = IkeaScrollLifecycleHandlers.device_added,
    doConfigure = IkeaScrollLifecycleHandlers.do_configure,
    driverSwitched = IkeaScrollLifecycleHandlers.driver_switched,
    infoChanged = IkeaScrollLifecycleHandlers.info_changed,
    init = IkeaScrollLifecycleHandlers.device_init,
  },
  subscribed_events = {
    [capabilities.button.ID] = button_subscribed_events,
  },
  supported_capabilities = {
    capabilities.button
  },
  can_handle = ikea_scroll_utils.is_ikea_scroll
}

return ikea_scroll_handler
