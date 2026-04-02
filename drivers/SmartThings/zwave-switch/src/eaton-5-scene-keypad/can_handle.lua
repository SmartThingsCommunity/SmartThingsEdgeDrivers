-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0



local function can_handle_eaton_5_scene_keypad(opts, driver, device, ...)
  local fingerprints = {
    {mfr = 0x001A, prod = 0x574D, model = 0x0000}, -- Eaton 5-Scene Keypad
  }
  for _, fingerprint in ipairs(fingerprints) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      local subdriver = require("eaton-5-scene-keypad")
      return true, subdriver
    end
  end
  return false
end

return can_handle_eaton_5_scene_keypad
