-- Sensi Lite ST25Z, Copeland model 1F76U-22ZB
local function can_handle_thermostat_sensi_st25z(opts, driver, device, ...)
  local MFR = 0x046B
  local PROD = 0x0004
  local MODEL = 0x0002

  if device:id_match(MFR, PROD, MODEL) then
    return true, require "thermostat-sensi-st25z"
  else
    return false
  end
end

return can_handle_thermostat_sensi_st25z
