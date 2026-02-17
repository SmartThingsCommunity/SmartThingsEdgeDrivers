-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local clusters = require "st.matter.clusters"
local capabilities = require "st.capabilities"
local switch_utils = require "switch_utils.utils"
local switch_fields = require "switch_utils.fields"
local scroll_fields = require "sub_drivers.ikea_scroll.scroll_utils.fields"

local IkeaScrollConfiguration = {}

function IkeaScrollConfiguration.build_button_component_map(device)
  local component_map = {
    main = {scroll_fields.ENDPOINTS_PUSH[1], scroll_fields.ENDPOINTS_UP_SCROLL[1], scroll_fields.ENDPOINTS_DOWN_SCROLL[1]},
    group2 = {scroll_fields.ENDPOINTS_PUSH[2], scroll_fields.ENDPOINTS_UP_SCROLL[2], scroll_fields.ENDPOINTS_DOWN_SCROLL[2]},
    group3 = {scroll_fields.ENDPOINTS_PUSH[3], scroll_fields.ENDPOINTS_UP_SCROLL[3], scroll_fields.ENDPOINTS_DOWN_SCROLL[3]},
  }
  device:set_field(switch_fields.COMPONENT_TO_ENDPOINT_MAP, component_map, {persist = true})
end

function IkeaScrollConfiguration.configure_buttons(device)
  for _, ep in ipairs(scroll_fields.ENDPOINTS_PUSH) do
    device:send(clusters.Switch.attributes.MultiPressMax:read(device, ep))
    switch_utils.set_field_for_endpoint(device, switch_fields.SUPPORTS_MULTI_PRESS, ep, true, {persist = true})
    device:emit_event_for_endpoint(ep, capabilities.button.button.pushed({state_change = false}))
  end
  for _, ep in ipairs(scroll_fields.ENDPOINTS_UP_SCROLL) do -- and by extension, ENDPOINTS_DOWN_SCROLL
    device:emit_event_for_endpoint(ep, capabilities.knob.supportedAttributes({"rotateAmount"}, {visibility = {displayed = false}}))
  end
end

function IkeaScrollConfiguration.match_profile(driver, device)
  device:try_update_metadata({profile = "ikea-scroll"})
  IkeaScrollConfiguration.build_button_component_map(device)
  IkeaScrollConfiguration.configure_buttons(device)
end

return IkeaScrollConfiguration
