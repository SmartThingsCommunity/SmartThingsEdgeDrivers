-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_v1_alarm(opts, driver, device, cmd, ...)
  return opts.dispatcher_class == "ZwaveDispatcher" and cmd ~= nil and cmd.version ~= nil and cmd.version == 1
end

return can_handle_v1_alarm
