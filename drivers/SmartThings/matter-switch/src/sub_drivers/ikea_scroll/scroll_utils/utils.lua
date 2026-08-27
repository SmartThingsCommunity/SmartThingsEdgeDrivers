-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local im = require "st.matter.interaction_model"
local clusters = require "st.matter.clusters"
local scroll_fields = require "sub_drivers.ikea_scroll.scroll_utils.fields"
local switch_fields = require "switch_utils.fields"

local IkeaScrollUtils = {}

-- override subscribe function in the main driver
function IkeaScrollUtils.subscribe(device)
  local subscribe_request = im.InteractionRequest(im.InteractionRequest.RequestType.SUBSCRIBE, {})
  for _, ep_push in ipairs(scroll_fields.ENDPOINTS_PUSH) do
    for _, switch_event in ipairs(scroll_fields.switch_press_subscribed_events) do
      local ib = im.InteractionInfoBlock(ep_push, clusters.Switch.ID, nil, switch_event)
      subscribe_request:with_info_block(ib)
    end
  end
  for _, ep_up in ipairs(scroll_fields.ENDPOINTS_UP_SCROLL) do
    for _, switch_event in ipairs(scroll_fields.switch_scroll_subscribed_events) do
      local ib = im.InteractionInfoBlock(ep_up, clusters.Switch.ID, nil, switch_event)
      subscribe_request:with_info_block(ib)
    end
  end
  for _, ep_down in ipairs(scroll_fields.ENDPOINTS_DOWN_SCROLL) do
    for _, switch_event in ipairs(scroll_fields.switch_scroll_subscribed_events) do
      local ib = im.InteractionInfoBlock(ep_down, clusters.Switch.ID, nil, switch_event)
      subscribe_request:with_info_block(ib)
    end
  end
  local cluster_id = clusters.PowerSource.ID
  local attr_id = clusters.PowerSource.attributes.BatPercentRemaining.ID
  local ib = im.InteractionInfoBlock(
    scroll_fields.ENDPOINT_POWER_SOURCE, cluster_id, attr_id
  )
  subscribe_request:with_info_block(ib)
  device:send(subscribe_request)

  local subscribed_attrs = device:get_field(switch_fields.SUBSCRIBED_ATTRIBUTES_KEY) or {}
  subscribed_attrs[cluster_id] = subscribed_attrs[cluster_id] or {}
  subscribed_attrs[cluster_id][attr_id] = ib
  device:set_field(switch_fields.SUBSCRIBED_ATTRIBUTES_KEY, subscribed_attrs)
end

return IkeaScrollUtils