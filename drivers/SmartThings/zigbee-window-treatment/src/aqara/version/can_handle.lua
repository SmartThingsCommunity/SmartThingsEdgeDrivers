-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function version_can_handle(opts, driver, device)
  local APPLICATION_VERSION = "application_version"
  local softwareVersion = device:get_field(APPLICATION_VERSION)
  if softwareVersion and softwareVersion ~= 34 then
    return true, require("aqara.version")
  end
  return false
end

return version_can_handle
