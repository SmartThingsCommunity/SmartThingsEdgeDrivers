local log = require "log"
local capabilities = require "st.capabilities"

local command_handlers = {}

-- callback to handle an `on` capability command
function command_handlers.switch_on(driver, device, command)
  log.debug(string.format("[%s] calling set_power(on)", device.device_network_id))
  device:emit_event(capabilities.switch.switch.on())
end

-- callback to handle an `off` capability command
function command_handlers.switch_off(driver, device, command)
  log.debug(string.format("[%s] calling set_power(off)", device.device_network_id))
  device:emit_event(capabilities.switch.switch.off())
end

return command_handlers
