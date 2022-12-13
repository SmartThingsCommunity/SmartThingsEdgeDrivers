local protocol = require "protocol"
local log = require "log"

local command_handlers = {}

function command_handlers.handle_switch_on(_, device)
    log.trace("switch on")
    protocol.send_switch_cmd(device, true)
end

function command_handlers.handle_switch_off(_, device)
    log.trace("switch off")
    protocol.send_switch_cmd(device, false)
end

function command_handlers.handle_set_level(_, device, command)
    log.trace("set level")
    protocol.send_switch_level_cmd(device, command.args.level)
end

function command_handlers.handle_refresh(_, device)
    log.trace("refresh")
    protocol.poll(_, device)
end

return command_handlers
