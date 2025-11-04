-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Basic
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })
--- @type st.zwave.CommandClass.SwitchBinary
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version = 2 })

local function binary_event_helper(driver, device, cmd)
  if cmd.src_channel > 0 then
    local value = cmd.args.value and cmd.args.value or cmd.args.target_value
    local event = value == SwitchBinary.value.OFF_DISABLE and capabilities.switch.switch.off() or capabilities.switch.switch.on()

    device:emit_event_for_endpoint(cmd.src_channel, event)

    if value == SwitchBinary.value.ON_ENABLE then
      device:emit_event(capabilities.switch.switch.on())
    else
      local all_off = true
      for i = 1,5 do
        if device:get_latest_state("switch"..i, capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
          all_off = false
          break
        end
      end

      if all_off then
        device:emit_event(capabilities.switch.switch.off())
      end
    end
  end
end

local function switch_set_helper(driver, device, value, command)
  if command.component == "main" then
    device:send_to_component(SwitchBinary:Set({ target_value=value, duration=0 }), "main")
    for comp_id, comp in pairs(device.profile.components) do
      if comp_id ~= "main" then
        device:send_to_component(SwitchBinary:Get({}), comp_id)
      end
    end
    device:emit_event(value == SwitchBinary.value.ON_ENABLE and capabilities.switch.switch.on() or capabilities.switch.switch.off())
  else
    device:send_to_component(SwitchBinary:Set({ target_value=value, duration=0 }), command.component)
    device:send_to_component(SwitchBinary:Get({}), command.component)
  end
end

local switch_on_handler = function(driver, device, command)
  switch_set_helper(driver, device, SwitchBinary.value.ON_ENABLE, command)
end

local switch_off_handler = function(driver, device, command)
  switch_set_helper(driver, device, SwitchBinary.value.OFF_DISABLE, command)
end

local function component_to_endpoint(device, component_id)
  if component_id == "main" then
    return { 1, 2, 3, 4, 5 }
  else
    local ep_num = component_id:match("switch(%d)")
    return { ep_num and tonumber(ep_num) }
  end
end

local function endpoint_to_component(device, ep)
  local switch_comp = string.format("switch%d", ep)
  if device.profile.components[switch_comp] ~= nil then
    return switch_comp
  else
    return "main"
  end
end

local device_init = function(self, device)
  device:set_component_to_endpoint_fn(component_to_endpoint)
  device:set_endpoint_to_component_fn(endpoint_to_component)
end

local zooz_power_strip = {
  NAME = "zooz power strip",
  lifecycle_handlers = {
    init = device_init
  },
  zwave_handlers = {
    [cc.BASIC] = {
      [Basic.REPORT] = binary_event_helper
    },
    [cc.SWITCH_BINARY] = {
      [SwitchBinary.REPORT] = binary_event_helper
    }
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = switch_on_handler,
      [capabilities.switch.commands.off.NAME] = switch_off_handler
    }
  },
  can_handle = require("zooz-power-strip.can_handle"),
}

return zooz_power_strip
