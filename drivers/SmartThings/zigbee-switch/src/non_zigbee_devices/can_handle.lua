return function(opts, driver, device)
  local st_device = require "st.device"

  if device.network_type ~= st_device.NETWORK_TYPE_ZIGBEE and device.network_type ~= st_device.NETWORK_TYPE_CHILD then
    return true, require("non_zigbee_devices")
  end
  return false
end
