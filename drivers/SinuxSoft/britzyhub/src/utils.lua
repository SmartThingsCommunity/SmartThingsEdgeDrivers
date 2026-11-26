-- SinuxSoft (c) 2025
-- Licensed under the Apache License, Version 2.0

local im = require "st.matter.interaction_model"
local log = require "log"

local utils = {}

-- Sends subscription request directly via device:send(), following the matter-switch pattern.
-- The default device:subscribe() reuses cached sessions, which causes timeout after hub
-- replacement because the hub Node ID changes and all sessions expire.
-- device:send() creates a new session directly, so it works correctly after hub replacement.
function utils.make_subscribe(subscribed_attributes)
  return function(device)
    local subscribe_request = im.InteractionRequest(im.InteractionRequest.RequestType.SUBSCRIBE, {})
    for cap_id, attributes in pairs(subscribed_attributes) do
      if device:supports_capability_by_id(cap_id) then
        for _, attr in ipairs(attributes) do
          local cluster_id = (attr._cluster and attr._cluster.ID) or attr.cluster
          local attr_id = attr.ID or attr.attribute
          local ib = im.InteractionInfoBlock(nil, cluster_id, attr_id)
          subscribe_request:with_info_block(ib)
        end
      end
    end
    if #subscribe_request.info_blocks > 0 then
      log.info_with({hub_logs=true}, string.format("[britzyhub] subscribe via send: %d blocks", #subscribe_request.info_blocks))
      device:send(subscribe_request)
    end
  end
end

return utils
