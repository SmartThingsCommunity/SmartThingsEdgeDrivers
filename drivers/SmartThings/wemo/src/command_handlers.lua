local protocol = require "protocol"

local command_handlers = {}

function command_handlers.handle_switch_on(driver, device)
  protocol.send_switch_cmd(device, true)
end

function command_handlers.handle_switch_off(driver, device)
  protocol.send_switch_cmd(device, false)
end

function command_handlers.handle_set_level(driver, device, command)
  protocol.send_switch_level_cmd(device, command.args.level)
end

function command_handlers.handle_refresh(driver, device)
  protocol.poll(device)
  if driver.server then
    driver.server:subscribe(device)
  end
end

return command_handlers
