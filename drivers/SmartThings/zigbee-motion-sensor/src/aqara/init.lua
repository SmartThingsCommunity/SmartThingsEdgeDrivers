local FINGERPRINTS = {
  { mfr = "LUMI", model = "lumi.motion.agl02" },
  { mfr = "LUMI", model = "lumi.motion.agl04" }
}

local is_aqara_products = function(opts, driver, device)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local aqara_motion_handler = {
  NAME = "Aqara Motion Handler",
  can_handle = is_aqara_products,
  sub_drivers = {
    require("aqara.motion-illuminance"),
    require("aqara.high-precision")
  }
}

return aqara_motion_handler
