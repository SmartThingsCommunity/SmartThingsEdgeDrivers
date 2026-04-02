-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local presence_utils = {}

-- used when presence events are based on battery reports
presence_utils.LAST_CHECKIN_TIMESTAMP = "lastCheckinTimestamp"

presence_utils.PRESENCE_CALLBACK_CREATE_FN = "presenceCallbackCreateFn"

-- events are based on battery reports
presence_utils.PRESENCE_CALLBACK_TIMER = "presenceCallbackTimer"

-- events are based on recurring poll of Basic cluster's attribute
presence_utils.RECURRING_POLL_TIMER = "recurringPollTimer"

function presence_utils.create_presence_timeout(device)
  local timer = device:get_field(presence_utils.PRESENCE_CALLBACK_TIMER)
  if timer ~= nil then
    device.thread:cancel_timer(timer)
  end
  local no_rep_timer = device:get_field(presence_utils.PRESENCE_CALLBACK_CREATE_FN)
  if (no_rep_timer ~= nil) then
    device:set_field(presence_utils.PRESENCE_CALLBACK_TIMER, no_rep_timer(device))
  end
end

return presence_utils
