-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local clusters = require "st.zigbee.zcl.clusters"
local utils = require "st.utils"
local zigbee_handlers = require "lock_handlers.zigbee_responses"

-- Yale (and ASSA ABLOY iRevo) locks hold their master code at user id 0.
local YALE_MASTER_USER_ID = 0
-- However, some Yale locks report the master code (though it can only be altered via user_id 0) as being at user_id 0xFFEE.
local YALE_UNKNOWN_USER_ID = 0xFFEE

-- Yale locks report some messages incorrectly: user ids may be in the high byte, and the master code (slot 0) may be
-- reported as 0xFFEE and/or with a non-master user type. Returns a corrected copy of `zb_rx`, leaving the original
-- untouched. Messages without a user type (e.g. operating events) only get their user id corrected.
local function normalize_user(zb_rx)
  local zcl_body = zb_rx.body.zcl_body
  local user_id = tonumber(zcl_body.user_id.value)
  local normalized_user_id = user_id
  if user_id >= 256 then
    normalized_user_id = (user_id == YALE_UNKNOWN_USER_ID) and YALE_MASTER_USER_ID or user_id >> 8
  end

  local master_type = clusters.DoorLock.types.DrlkUserType.MASTER_USER
  local needs_master_type = normalized_user_id == YALE_MASTER_USER_ID and zcl_body.user_type ~= nil
    and zcl_body.user_type.value ~= master_type
  if normalized_user_id == user_id and not needs_master_type then
    return zb_rx
  end

  local new_zb_rx = utils.deep_copy(zb_rx)
  new_zb_rx.body.zcl_body.user_id.value = normalized_user_id
  if needs_master_type then
    new_zb_rx.body.zcl_body.user_type.value = master_type
  end
  return new_zb_rx
end

-- Wraps main driver's attribute handlers so that messages are all parsed with a corrected user id.
local function normalizing_response(handler)
  return function(driver, device, zb_rx)
    handler(driver, device, normalize_user(zb_rx))
  end
end

local yale_lock_driver = {
  NAME = "Yale Lock",
  zigbee_handlers = {
    cluster = {
      [clusters.DoorLock.ID] = {
        [clusters.DoorLock.client.commands.GetPINCodeResponse.ID] = normalizing_response(zigbee_handlers.get_pin_code_response),
        [clusters.DoorLock.client.commands.ProgrammingEventNotification.ID] = normalizing_response(zigbee_handlers.programming_event_notification),
        [clusters.DoorLock.client.commands.OperatingEventNotification.ID] = normalizing_response(zigbee_handlers.operating_event_notification),
      }
    }
  },
  sub_drivers = require("yale.sub_drivers"),
  can_handle = require("yale.can_handle")
}

return yale_lock_driver
