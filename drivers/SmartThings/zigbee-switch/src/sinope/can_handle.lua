return function(opts, driver, device, ...)
    local can_handle = device:get_manufacturer() == "Sinope Technologies" and device:get_model() == "SW2500ZB"
    if can_handle then
      local subdriver = require("sinope")
      return true, subdriver
    else
      return false
    end
  end
