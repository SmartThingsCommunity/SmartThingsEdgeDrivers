-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local im = require "st.matter.interaction_model"
local clusters = require "st.matter.clusters"
local scroll_fields = require "sub_drivers.ikea_scroll.scroll_utils.fields"

local IkeaScrollUtils = {}

-- override subscribe function to prevent subscribing to additional events from the main driver
function IkeaScrollUtils.subscribe(device)
  local subscribe_request = im.InteractionRequest(im.InteractionRequest.RequestType.SUBSCRIBE, {})
  for _, ep_press in ipairs(scroll_fields.ENDPOINTS_PRESS) do
    for _, switch_event in ipairs(scroll_fields.switch_press_subscribed_events) do
      local ib = im.InteractionInfoBlock(ep_press, clusters.Switch.ID, nil, switch_event)
      subscribe_request:with_info_block(ib)
    end
  end
  local ib = im.InteractionInfoBlock(
    scroll_fields.ENDPOINT_POWER_SOURCE, clusters.PowerSource.ID, clusters.PowerSource.attributes.BatPercentRemaining.ID
  )
  subscribe_request:with_info_block(ib)
  device:send(subscribe_request)
end

return IkeaScrollUtils