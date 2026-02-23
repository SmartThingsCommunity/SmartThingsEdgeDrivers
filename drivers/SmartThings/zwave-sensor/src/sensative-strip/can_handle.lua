-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_sensative_strip(opts, driver, device, cmd, ...)
  local SENSATIVE_MFR = 0x019A
  local SENSATIVE_MODEL = 0x000A
  if device:id_match(SENSATIVE_MFR, nil, SENSATIVE_MODEL) then
    local subdriver = require("sensative-strip")
    return true, subdriver
  end
  return false
end

return can_handle_sensative_strip
