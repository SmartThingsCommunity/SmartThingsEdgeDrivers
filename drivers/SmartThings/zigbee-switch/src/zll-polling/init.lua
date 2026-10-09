-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local device_lib = require "st.device"
local clusters = require "st.zigbee.zcl.clusters"
local configurationMap = require "configurations"

local INFREQUENT_POLL_COUNTER = "_infrequent_poll_counter"
local ZLL_POLL_TIMER = "_zll_poll_timer"

local function do_zll_poll(device)
  if device == nil or type(device.get_field) ~= "function" then
    return
  end

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

local function set_up_zll_polling(driver, device)
  -- only set this up for non-child devices
  if device.network_type ~= device_lib.NETWORK_TYPE_ZIGBEE then
    return
  end

  -- should never happen, but defensive check
  local existing_timer = device:get_field(ZLL_POLL_TIMER)
  if existing_timer ~= nil then
    device.thread:cancel_timer(existing_timer)
  end

  local timer = device.thread:call_on_schedule(5 * 60, function()
      do_zll_poll(device)
  end, "zll_polling")

  device:set_field(ZLL_POLL_TIMER, timer)
end

local function remove_zll_polling(driver, device)
  local existing_timer = device:get_field(ZLL_POLL_TIMER)
  if existing_timer ~= nil then
    device.thread:cancel_timer(existing_timer)
    device:set_field(ZLL_POLL_TIMER, nil)
  end
end

local ZLL_polling = {
  NAME = "ZLL Polling",
  lifecycle_handlers = {
    init = configurationMap.reconfig_wrapper(set_up_zll_polling),
    removed = remove_zll_polling
  },
  can_handle = require("zll-polling.can_handle"),
}

return ZLL_polling
