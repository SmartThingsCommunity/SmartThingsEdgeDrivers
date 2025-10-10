return function(opts, driver, device)
  local ZLL_DIMMER_BULB_FINGERPRINTS = require "zll-dimmer-bulb.fingerprints"
  local can_handle = (ZLL_DIMMER_BULB_FINGERPRINTS[device:get_manufacturer()] or {})[device:get_model()]
  if can_handle then
    local subdriver = require("zll-dimmer-bulb")
    return true, subdriver
  else
    return false
  end
end
