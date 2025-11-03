
local fingerprints = require("eaton-5-scene-keypad.fingerprints")

local function can_handle_eaton_5_scene_keypad(opts, driver, device, ...)
  for _, fingerprint in ipairs(fingerprints) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      local subdriver = require("eaton-5-scene-keypad")
      return true, subdriver
    end
  end
  return false
end

return can_handle_eaton_5_scene_keypad