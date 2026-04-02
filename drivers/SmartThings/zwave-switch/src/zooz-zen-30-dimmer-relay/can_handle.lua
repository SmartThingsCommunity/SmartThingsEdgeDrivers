-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_zooz_zen_30_dimmer_relay_double_switch(opts, driver, device, ...)
  local fingerprints = {
    { mfr = 0x027A, prod = 0xA000, model = 0xA008 } -- Zooz Zen 30 Dimmer Relay Double Switch
  }
  for _, fingerprint in ipairs(fingerprints) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      local subdriver = require("zooz-zen-30-dimmer-relay")
      return true, subdriver
    end
  end
  return false
end

return can_handle_zooz_zen_30_dimmer_relay_double_switch
