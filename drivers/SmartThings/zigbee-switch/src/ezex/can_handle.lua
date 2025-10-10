return function(opts, driver, device)
  local ZIGBEE_METERING_SWITCH_FINGERPRINTS = {
    { model = "E240-KR116Z-HA" }
  }

  for _, fingerprint in ipairs(ZIGBEE_METERING_SWITCH_FINGERPRINTS) do
    if device:get_model() == fingerprint.model then
      local subdriver = require("ezex")
      return true, subdriver
    end
  end

  return false
end
