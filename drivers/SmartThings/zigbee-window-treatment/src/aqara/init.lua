local aqara_utils = require "aqara/aqara_utils"

local function is_aqara_products(opts, driver, device)
  for _, fingerprint in ipairs(aqara_utils.FINGERPRINTS) do
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
