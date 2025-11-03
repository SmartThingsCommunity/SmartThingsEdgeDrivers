local fingerprints = require("inovelli-2-channel-smart-plug.fingerprints")

local function can_handle_inovelli_2_channel_smart_plug(opts, driver, device, ...)
  for _, fingerprint in ipairs(fingerprints) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      local subdriver = require("inovelli-2-channel-smart-plug")
      return true, subdriver
    end
  end
  return false
end

return can_handle_inovelli_2_channel_smart_plug