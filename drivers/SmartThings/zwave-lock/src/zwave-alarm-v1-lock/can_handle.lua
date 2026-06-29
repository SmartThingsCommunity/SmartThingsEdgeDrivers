-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_v1_alarm(opts, driver, device, cmd, ...)
  if opts.dispatcher_class == "ZwaveDispatcher" and cmd ~= nil and cmd.version ~= nil and cmd.version == 1 then
    return true, require("zwave-alarm-v1-lock")
  end
  return false
end

return can_handle_v1_alarm
