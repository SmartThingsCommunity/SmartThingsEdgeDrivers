-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local constants = require "qubino-switches.constants.qubino-constants"

local function can_handle_qubino_flush_relay(opts, driver, device, cmd, ...)
  if device:id_match(constants.QUBINO_MFR) then
    local subdriver = require("qubino-switches")
    return true, subdriver
  end
  return false
end

return can_handle_qubino_flush_relay
