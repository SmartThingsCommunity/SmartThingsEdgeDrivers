local fingerprints = require("fibaro-wall-plug-us.fingerprints")

local function can_handle_fibaro_wall_plug(opts, driver, device, ...)
  for _, fingerprint in ipairs(fingerprints) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      local subdriver = require("fibaro-wall-plug-us")
      return true, subdriver
    end
  end
  return false
end

return can_handle_fibaro_wall_plug