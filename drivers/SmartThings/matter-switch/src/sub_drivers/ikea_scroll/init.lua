-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local im = require "st.matter.interaction_model"
local switch_utils = require "utils.switch_utils"
local fields = require "utils.switch_fields"


-- SUB-DRIVER SPECIFIC FIELDS

local ENDPOINTS_PRESS = {3, 6, 9}

local button_subscribed_events = {
  clusters.Switch.events.MultiPressComplete.ID,
  clusters.Switch.events.LongPress.ID,
}

-- UTIL FUNCTIONS --

local IkeaScrollUtils = {}

function IkeaScrollUtils.is_ikea_scroll(opts, driver, device)
  return switch_utils.get_product_override_field(device, "is_ikea_scroll")
end

-- override subscribe function to prevent subscribing to additional events from the main driver
function IkeaScrollUtils.subscribe(device)
  local subscribe_request = im.InteractionRequest(im.InteractionRequest.RequestType.SUBSCRIBE, {})
  for _, ep_press in ipairs(ENDPOINTS_PRESS) do
    for _, switch_event in ipairs(button_subscribed_events) do
      local ib = im.InteractionInfoBlock(ep_press, clusters.Switch.ID, nil, switch_event)
      subscribe_request:with_info_block(ib)
    end
  end
  device:send(subscribe_request)
end

function IkeaScrollUtils.build_button_component_map(device)
  local component_map = {
    group1 = ENDPOINTS_PRESS[1],
    group2 = ENDPOINTS_PRESS[2],
    group3 = ENDPOINTS_PRESS[3],
  }
  device:set_field(fields.COMPONENT_TO_ENDPOINT_MAP, component_map, {persist = true})
end

function IkeaScrollUtils.configure_buttons(device)
  for _, ep_press in ipairs(ENDPOINTS_PRESS) do
    device:send(clusters.Switch.attributes.MultiPressMax:read(device, ep_press))
    device:emit_event_for_endpoint(ep_press, capabilities.button.button.pushed({state_change = false}))
  end
end

function IkeaScrollUtils.match_profile(driver, device)
  device:try_update_metadata({profile = "ikea-scroll"})
  IkeaScrollUtils.build_button_component_map(device)
  IkeaScrollUtils.configure_buttons(device)
end


-- LIFECYCLE HANDLERS --

local IkeaScrollLifecycleHandlers = {}

-- prevent main driver device_added handling from running
function IkeaScrollLifecycleHandlers.device_added(driver, device)
end

function IkeaScrollLifecycleHandlers.device_init(driver, device)
  device:set_endpoint_to_component_fn(switch_utils.endpoint_to_component)
  device:extend_device("subscribe", IkeaScrollUtils.subscribe)
  device:subscribe()
end

function IkeaScrollLifecycleHandlers.do_configure(driver, device)
  IkeaScrollUtils.match_profile(driver, device)
end

function IkeaScrollLifecycleHandlers.driver_switched(driver, device)
  IkeaScrollUtils.match_profile(driver, device)
end

function IkeaScrollLifecycleHandlers.info_changed(driver, device, event, args)
  if device.profile.id ~= args.old_st_store.profile.id then
    IkeaScrollUtils.configure_buttons(device)
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
  can_handle = IkeaScrollUtils.is_ikea_scroll
}

return ikea_scroll_handler
