-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device, cmd)
  if opts.dispatcher_class == "ZwaveDispatcher" and cmd ~= nil and cmd.version ~= nil and cmd.version == 1 then
    local subdriver = require("using-old-capabilities.zwave-alarm-v1-lock")
    return true, subdriver
  end
  return false
end