local AEOTEC_HOME_ENERGY_METER_GEN8_FINGERPRINTS = {
  { mfr = 0x0371, prod = 0x0003, model = 0x0033 }, -- HEM Gen8 1 Phase EU
  { mfr = 0x0371, prod = 0x0003, model = 0x0034 }, -- HEM Gen8 3 Phase EU
  { mfr = 0x0371, prod = 0x0103, model = 0x002E }, -- HEM Gen8 2 Phase US
  { mfr = 0x0371, prod = 0x0102, model = 0x002E }, -- HEM Gen8 1 Phase AU
  { mfr = 0x0371, prod = 0x0102, model = 0x0034 }, -- HEM Gen8 3 Phase AU
}

local function can_handle_aeotec_meter_gen8(opts, driver, device, ...)
  for _, fingerprint in ipairs(AEOTEC_HOME_ENERGY_METER_GEN8_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      local subdriver = require("aeotec-home-energy-meter-gen8")
      return true, subdriver
    end
  end
  return false
end

local function device_added(driver, device)
  device:refresh()
end

local aeotec_home_energy_meter_gen8 = {
  NAME = "Aeotec Home Energy Meter Gen8",
  lifecycle_handlers = {
    added = device_added
  },
  can_handle = can_handle_aeotec_meter_gen8,
  sub_drivers = {
    require("aeotec-home-energy-meter-gen8/1-phase"),
    require("aeotec-home-energy-meter-gen8/2-phase"),
    require("aeotec-home-energy-meter-gen8/3-phase")
  }
}

return aeotec_home_energy_meter_gen8
