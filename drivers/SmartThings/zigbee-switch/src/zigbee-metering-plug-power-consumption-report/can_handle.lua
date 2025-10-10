return function(opts, driver, device, ...)
  local can_handle = device:get_manufacturer() == "DAWON_DNS"
  if can_handle then
    local subdriver = require("zigbee-metering-plug-power-consumption-report")
    return true, subdriver
  else
    return false
  end
end
