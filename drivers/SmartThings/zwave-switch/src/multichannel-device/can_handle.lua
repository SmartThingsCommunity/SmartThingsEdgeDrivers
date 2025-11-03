local capabilities = require "st.capabilities"

local function can_handle_multichannel_device(opts, driver, device, ...)
  if device:supports_capability(capabilities.zwMultichannel) then
    local subdriver = require("multichannel-device")
    return true, subdriver
  end
  return false
end

return can_handle_multichannel_device