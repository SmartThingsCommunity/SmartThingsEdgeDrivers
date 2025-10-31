-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local im = require "st.matter.interaction_model"
local clusters = require "st.matter.clusters"
local switch_utils = require "switch_utils.utils"
local scroll_fields = require "sub_drivers.ikea_scroll.scroll_utils.fields"

local IkeaScrollUtils = {}

function IkeaScrollUtils.is_ikea_scroll(opts, driver, device)
  return switch_utils.get_product_override_field(device, "is_ikea_scroll")
end

-- override subscribe function to prevent subscribing to additional events from the main driver
function IkeaScrollUtils.subscribe(device)
  local subscribe_request = im.InteractionRequest(im.InteractionRequest.RequestType.SUBSCRIBE, {})
  for _, ep_press in ipairs(scroll_fields.ENDPOINTS_PRESS) do
    for _, switch_event in ipairs(scroll_fields.switch_press_subscribed_events) do
      print("##", ep_press)
      local ib = im.InteractionInfoBlock(ep_press, clusters.Switch.ID, nil, switch_event)
      subscribe_request:with_info_block(ib)
    end
  end
  device:send(subscribe_request)
end

return IkeaScrollUtils