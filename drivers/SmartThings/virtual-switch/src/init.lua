local capabilities = require "st.capabilities"
local Driver = require "st.driver"
local additional_fields = {
  state_change = true
}


local function handle_set_level(driver, device, command)
  if (command.args.level == 0) then
    device:emit_event(capabilities.switch.switch.off(additional_fields))
  else
    device:emit_event(capabilities.switchLevel.level(command.args.level, additional_fields))
    device:emit_event(capabilities.switch.switch.on())
  end

end

local function handle_on(driver, device, command)
  device:emit_event(capabilities.switch.switch.on(additional_fields))
end

local function handle_off(driver, device, command)
  device:emit_event(capabilities.switch.switch.off(additional_fields))
end

local virtual_driver = Driver("virtual-switch", {
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = handle_on,
      [capabilities.switch.commands.off.NAME] = handle_off,
    },
    [capabilities.switchLevel.ID] = {
        [capabilities.switchLevel.commands.setLevel.NAME] = handle_set_level
    },
  }
})

virtual_driver:run()
