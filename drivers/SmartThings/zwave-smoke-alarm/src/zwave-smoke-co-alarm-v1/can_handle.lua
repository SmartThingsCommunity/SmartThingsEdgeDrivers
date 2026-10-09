-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_v1_alarm(opts, driver, device, cmd, ...)
  -- The default handlers for the Alarm/Notification command class(es) for the
  -- Smoke Detector and Carbon Monoxide Detector only handles V3 and up.
  if opts.dispatcher_class == "ZwaveDispatcher" and cmd ~= nil and cmd.version ~= nil and cmd.version < 3 then
    return true, require("zwave-smoke-co-alarm-v1")
  end
  return false
end

return can_handle_v1_alarm
