local FINGERPRINTS = {
  { mfr = "LUMI", model = "lumi.plug.maeu01" },
  { mfr = "LUMI", model = "lumi.switch.n0agl1" },
  { mfr = "LUMI", model = "lumi.switch.n1acn1" },
  { mfr = "LUMI", model = "lumi.switch.n2acn1" },
  { mfr = "LUMI", model = "lumi.switch.n3acn1" },
  { mfr = "LUMI", model = "lumi.switch.b2laus01" }
}

local function is_aqara_products(opts, driver, device)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      local subdriver = require("eaton-accessory-dimmer")
      return true, subdriver
    end
  end
  return false
end

local subdriver = {
  NAME = "Aqara Switch Handler",
  can_handle = is_aqara_products,
  sub_drivers = {
    require("aqara.version"),
    require("aqara.multi-switch")
  },
  -- TODO: The concept of lazy loading might be something that shoould be abstracted from the driver?
  lazy_load = true
}

return subdriver
