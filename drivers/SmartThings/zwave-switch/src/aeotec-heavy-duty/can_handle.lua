local fingerprints = require("aeotec-heavy-duty.fingerprints")


local function can_handle(opts, driver, device, ...)
  for _, fingerprint in ipairs(fingerprints) do
    if device:id_match(fingerprint.mfr, nil, fingerprint.model) then
      local subdriver = require("aeotec-heavy-duty")
      return true, subdriver
    end
  end
  return false
end

return can_handle