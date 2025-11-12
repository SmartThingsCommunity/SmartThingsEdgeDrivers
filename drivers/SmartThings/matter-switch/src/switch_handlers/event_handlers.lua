-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local lua_socket = require "socket"
local fields = require "switch_utils.fields"
local switch_utils = require "switch_utils.utils"

local EventHandlers = {}


-- [[ SWITCH CLUSTER EVENTS ]] --

function EventHandlers.initial_press_handler(driver, device, ib, response)
  if switch_utils.get_field_for_endpoint(device, fields.SUPPORTS_MULTI_PRESS, ib.endpoint_id) then
    -- Receipt of an InitialPress event means we do not want to ignore the next MultiPressComplete event
    -- or else we would potentially not create the expected button capability event
    switch_utils.set_field_for_endpoint(device, fields.IGNORE_NEXT_MPC, ib.endpoint_id, nil)
  elseif switch_utils.get_field_for_endpoint(device, fields.INITIAL_PRESS_ONLY, ib.endpoint_id) then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.button.button.pushed({state_change = true}))
  elseif switch_utils.get_field_for_endpoint(device, fields.EMULATE_HELD, ib.endpoint_id) then
    -- if our button doesn't differentiate between short and long holds, do it in code by keeping track of the press down time
    switch_utils.set_field_for_endpoint(device, fields.START_BUTTON_PRESS, ib.endpoint_id, lua_socket.gettime(), {persist = false})
  end
end

-- if the device distinguishes a long press event, it will always be a "held"
-- there's also a "long release" event, but this event is required to come first
function EventHandlers.long_press_handler(driver, device, ib, response)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.button.button.held({state_change = true}))
  if switch_utils.get_field_for_endpoint(device, fields.SUPPORTS_MULTI_PRESS, ib.endpoint_id) then
    -- Ignore the next MultiPressComplete event if it is sent as part of this "long press" event sequence
    switch_utils.set_field_for_endpoint(device, fields.IGNORE_NEXT_MPC, ib.endpoint_id, true)
  end
end

function EventHandlers.multi_press_complete_handler(driver, device, ib, response)
  -- in the case of multiple button presses
  -- emit number of times, multiple presses have been completed
  if ib.data and not switch_utils.get_field_for_endpoint(device, fields.IGNORE_NEXT_MPC, ib.endpoint_id) then
    local press_value = ib.data.elements.total_number_of_presses_counted.value
    --capability only supports up to 6 presses
    if press_value < 7 then
      local button_event = capabilities.button.button.pushed({state_change = true})
      if press_value == 2 then
        button_event = capabilities.button.button.double({state_change = true})
      elseif press_value > 2 then
        button_event = capabilities.button.button(string.format("pushed_%dx", press_value), {state_change = true})
      end

      device:emit_event_for_endpoint(ib.endpoint_id, button_event)
    else
      device.log.info(string.format("Number of presses (%d) not supported by capability", press_value))
    end
  end
  switch_utils.set_field_for_endpoint(device, fields.IGNORE_NEXT_MPC, ib.endpoint_id, nil)
end

local function emulate_held_event(device, ep)
  local now = lua_socket.gettime()
  local press_init = switch_utils.get_field_for_endpoint(device, fields.START_BUTTON_PRESS, ep) or now -- if we don't have an init time, assume instant release
  if (now - press_init) < fields.TIMEOUT_THRESHOLD then
    if (now - press_init) > fields.HELD_THRESHOLD then
      device:emit_event_for_endpoint(ep, capabilities.button.button.held({state_change = true}))
    else
      device:emit_event_for_endpoint(ep, capabilities.button.button.pushed({state_change = true}))
    end
  end
  switch_utils.set_field_for_endpoint(device, fields.START_BUTTON_PRESS, ep, nil, {persist = false})
end

function EventHandlers.short_release_handler(driver, device, ib, response)
  if not switch_utils.get_field_for_endpoint(device, fields.SUPPORTS_MULTI_PRESS, ib.endpoint_id) then
    if switch_utils.get_field_for_endpoint(device, fields.EMULATE_HELD, ib.endpoint_id) then
      emulate_held_event(device, ib.endpoint_id)
    else
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.button.button.pushed({state_change = true}))
    end
  end
end

return EventHandlers