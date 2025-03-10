local capabilities = require "st.capabilities"
local Driver = require "st.driver"

local function force_state_change(device)
  if device.preferences == nil or device.preferences["certifiedpreferences.forceStateChange"] == nil then
    return {state_change = true}
  elseif not device.preferences["certifiedpreferences.forceStateChange"] then
    return nil
  else
    return {state_change = true}
  end
end

local function handle_set_level(driver, device, command)
  if (command.args.level == 0) then
    device:emit_event(capabilities.switch.switch.off(force_state_change(device)))
  else
    device:emit_event(capabilities.switchLevel.level(command.args.level, force_state_change(device)))
    device:emit_event(capabilities.switch.switch.on())
  end

end

local function handle_on(driver, device, command)
  device:emit_event(capabilities.switch.switch.on(force_state_change(device)))
end

local function handle_off(driver, device, command)
  device:emit_event(capabilities.switch.switch.off(force_state_change(device)))
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
