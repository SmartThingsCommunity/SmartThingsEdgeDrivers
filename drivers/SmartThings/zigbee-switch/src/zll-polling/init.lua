-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local device_lib = require "st.device"
local clusters = require "st.zigbee.zcl.clusters"

local function set_up_zll_polling(driver, device)
  local INFREQUENT_POLL_COUNTER = "_infrequent_poll_counter"
  local function poll()
    local infrequent_counter = device:get_field(INFREQUENT_POLL_COUNTER) or 1
    if infrequent_counter == 12 then
      -- do a full refresh once an hour
      device:refresh()
      infrequent_counter = 0
    else
      -- Read On/Off every poll
      for _, ep in pairs(device.zigbee_endpoints) do
        if device:supports_server_cluster(clusters.OnOff.ID, ep.id) then
          device:send(clusters.OnOff.attributes.OnOff:read(device):to_endpoint(ep.id))
        end
      end
      infrequent_counter = infrequent_counter + 1
    end
    device:set_field(INFREQUENT_POLL_COUNTER, infrequent_counter)
  end

  -- only set this up for non-child devices
  if device.network_type == device_lib.NETWORK_TYPE_ZIGBEE then
    device.thread:call_on_schedule(5 * 60, poll, "zll_polling")
  end
end

local ZLL_polling = {
  NAME = "ZLL Polling",
  lifecycle_handlers = {
    init = set_up_zll_polling
  },
  can_handle = require("zll-polling.can_handle"),
}

return ZLL_polling
