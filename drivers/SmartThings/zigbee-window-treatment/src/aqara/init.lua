local capabilities = require "st.capabilities"

local FINGERPRINTS = {
  { mfr = "LUMI", model = "lumi.curtain" },
  { mfr = "LUMI", model = "lumi.curtain.v1" },
  { mfr = "LUMI", model = "lumi.curtain.aq2" }
}

local function is_aqara_products(opts, driver, device)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local aqara_window_treatment_handler = {
  NAME = "Aqara Window Treatment Handler",
  sub_drivers = {
    require("aqara.curtain"),
    require("aqara.roller-shade")
  },
  can_handle = is_aqara_products
}

return aqara_window_treatment_handler
