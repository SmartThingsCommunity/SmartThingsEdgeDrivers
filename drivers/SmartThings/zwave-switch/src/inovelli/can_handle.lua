-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local INOVELLI_FINGERPRINTS = {
  { mfr = 0x031E, prod = 0x0017, model = 0x0001 }, -- Inovelli VZW32-SN
  { mfr = 0x031E, prod = 0x0015, model = 0x0001 }, -- Inovelli VZW31-SN
  { mfr = 0x031E, prod = 0x0001, model = 0x0001 }, -- Inovelli LZW31SN
  { mfr = 0x031E, prod = 0x0003, model = 0x0001 }, -- Inovelli LZW31
}

local function can_handle_inovelli(opts, driver, device, ...)
  for _, fingerprint in ipairs(INOVELLI_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      local subdriver = require("inovelli")
      return true, subdriver
    end
  end
  return false
end

return can_handle_inovelli